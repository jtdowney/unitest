import { milliseconds as millisecondsToDuration } from "../gleam_time/gleam/time/duration.mjs";
import {
  SKIP_SYMBOL,
  runTest as runTestCommon,
  parseStack,
  timeoutResult,
} from "./unitest_common_ffi.mjs";
import { TestResult$TestResult as testResult } from "./unitest.mjs";
import { from_dynamic as decodeTestRunResult } from "./unitest/internal/outcome.mjs";

// Extra slack on the parent watchdog past timeoutMs. The worker times out async
// tests precisely on its own; this margin keeps the watchdog (a sync-hang
// backstop) from racing that and terminating a worker that was about to report.
const WORKER_WATCHDOG_GRACE_MS = 100;

function makeGenericError(message) {
  return decodeTestRunResult({ kind: "error", message });
}

function crashedOutcome(error) {
  return decodeTestRunResult({
    kind: "error",
    failureKind: {
      type: "crashed",
      reason: error == null ? String(error) : error.message || String(error),
      stack: parseStack(error),
    },
  });
}

// Main-thread timeout for the sequential, async, and promise-fallback paths.
function withTimeout(promise, timeoutMs) {
  if (!timeoutMs || timeoutMs <= 0)
    return promise.then(
      (r) => ({ outcome: r }),
      (err) => ({ error: err }),
    );
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      resolve({ timedOut: true });
    }, timeoutMs);
    promise.then(
      (r) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ outcome: r });
      },
      (err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ error: err });
      },
    );
  });
}

// Map a settled withTimeout record onto a decoded test outcome.
function settledToOutcome(result, timeoutMs) {
  if (result.timedOut) {
    return decodeTestRunResult(timeoutResult(timeoutMs));
  }
  if (result.error !== undefined) {
    return crashedOutcome(result.error);
  }
  return result.outcome;
}

function detectRuntime() {
  if (typeof Deno !== "undefined") return "deno";
  if (typeof process !== "undefined") return "node";
  return null;
}

const runtime = detectRuntime();

const nodeOs = runtime === "node" ? await import("node:os") : null;
const nodeWorkerThreads =
  runtime === "node" ? await import("node:worker_threads") : null;

export function defaultWorkers() {
  if (nodeOs) {
    const count =
      typeof nodeOs.availableParallelism === "function"
        ? nodeOs.availableParallelism()
        : nodeOs.cpus().length;
    return Math.max(1, count | 0);
  }
  return 1;
}

export function nowMs() {
  return Math.round(performance.now());
}

export function currentTarget() {
  return "javascript";
}

export function halt(code) {
  if (runtime === "node") {
    process.exitCode = code;
  } else if (runtime === "deno") {
    Deno.exitCode = code;
  }
}

export function yieldThen(next) {
  if (typeof setImmediate !== "undefined") {
    setImmediate(() => next());
  } else {
    setTimeout(() => next(), 0);
  }
}

export function skip() {
  throw { [SKIP_SYMBOL]: true };
}

async function runTest(test, packageName, checkResults) {
  const moduleUrl = new URL(
    `../${packageName}/${test.module}.mjs`,
    import.meta.url,
  ).href;
  const raw = await runTestCommon(
    moduleUrl,
    test.name,
    checkResults,
    test.module,
  );
  return decodeTestRunResult(raw);
}

export function runTestAsync(test, packageName, checkResults, timeoutMs, next) {
  withTimeout(runTest(test, packageName, checkResults), timeoutMs).then(
    (result) => next(settledToOutcome(result, timeoutMs)),
  );
}

let poolResultQueue = [];
let poolWaitingCallback = null;

function resetPoolState() {
  poolResultQueue = [];
  poolWaitingCallback = null;
}

function deliverPoolResult(pr) {
  if (poolWaitingCallback) {
    const cb = poolWaitingCallback;
    poolWaitingCallback = null;
    cb(pr);
  } else {
    poolResultQueue.push(pr);
  }
}

function gleamGroupsToArrays(moduleGroups) {
  return moduleGroups.toArray().map((g) => g.toArray());
}

export function startModulePool(
  moduleGroups,
  packageName,
  checkResults,
  timeoutMs,
  workers,
) {
  resetPoolState();
  const groups = gleamGroupsToArrays(moduleGroups);

  if (nodeWorkerThreads) {
    try {
      startWithWorkerThreads(
        groups,
        packageName,
        checkResults,
        timeoutMs,
        workers,
      );
    } catch {
      startWithPromises(groups, packageName, checkResults, timeoutMs, workers);
    }
  } else {
    startWithPromises(groups, packageName, checkResults, timeoutMs, workers);
  }
}

export function startAsyncPool(
  moduleGroups,
  packageName,
  checkResults,
  timeoutMs,
  workers,
) {
  resetPoolState();
  startWithPromises(
    gleamGroupsToArrays(moduleGroups),
    packageName,
    checkResults,
    timeoutMs,
    workers,
  );
}

function startWithPromises(
  groups,
  packageName,
  checkResults,
  timeoutMs,
  workers,
) {
  const queue = [...groups];
  let inFlight = 0;
  const limit = Math.max(1, workers | 0);
  const testLimit = defaultWorkers();

  const pump = () => {
    while (inFlight < limit && queue.length > 0) {
      const tests = queue.shift();
      inFlight += 1;

      let testInFlight = 0;
      let testIndex = 0;
      let completed = 0;

      const pumpTests = () => {
        while (testInFlight < testLimit && testIndex < tests.length) {
          const test = tests[testIndex++];
          testInFlight += 1;
          const start = nowMs();
          withTimeout(runTest(test, packageName, checkResults), timeoutMs)
            .then((r) => {
              deliverPoolResult(
                testResult(
                  test,
                  settledToOutcome(r, timeoutMs),
                  millisecondsToDuration(nowMs() - start),
                ),
              );
            })
            .finally(() => {
              testInFlight -= 1;
              completed += 1;
              if (completed === tests.length) {
                inFlight -= 1;
                pump();
              } else {
                pumpTests();
              }
            });
        }
      };
      pumpTests();
    }
  };

  pump();
}

// Regroup a flat run of tests by module so the promise fallback keeps its
// per-module-group concurrency semantics.
function groupByModule(tests) {
  const groups = [];
  let current = null;
  for (const test of tests) {
    if (current === null || current[0].module !== test.module) {
      current = [];
      groups.push(current);
    }
    current.push(test);
  }
  return groups;
}

function startWithWorkerThreads(
  groups,
  packageName,
  checkResults,
  timeoutMs,
  workers,
) {
  const { Worker } = nodeWorkerThreads;
  const queue = groups.flat();
  const limit = Math.max(1, workers | 0);
  const workerCount = Math.min(limit, queue.length);

  if (workerCount === 0) return;

  const workerUrl = new URL("./unitest_worker_ffi.mjs", import.meta.url);

  let workerFailures = 0;
  const maxWorkerFailures = 3;

  // Backstop for *synchronous* hangs only: the worker times out async tests
  // itself, so this watchdog just catches a worker wedged by sync code that
  // blocks its event loop.
  const watchdogMs = timeoutMs + WORKER_WATCHDOG_GRACE_MS;
  function armWatchdog(w) {
    if (timeoutMs && timeoutMs > 0) {
      w._watchdog = setTimeout(() => {
        w._timedOut = true;
        w.terminate();
      }, watchdogMs);
    }
  }

  function clearWatchdog(w) {
    if (w._watchdog) {
      clearTimeout(w._watchdog);
      w._watchdog = null;
    }
  }

  // Send exactly one test from the shared queue and arm a fresh per-test
  // watchdog.
  function sendNext(w) {
    const test = queue.shift();
    if (test === undefined) {
      w._done = true;
      w.terminate();
      return;
    }
    w._activeTest = test;
    w._timedOut = false;
    armWatchdog(w);
    w.postMessage({
      type: "run",
      moduleUrl: new URL(
        `../${packageName}/${test.module}.mjs`,
        import.meta.url,
      ).href,
      moduleName: test.module,
      fnName: test.name,
      checkResults,
      timeoutMs,
    });
  }

  function recycleWorker(w) {
    w._done = true;
    w.terminate();
    if (queue.length > 0) {
      spawnWorker();
    }
  }

  function handleWorkerDeath(w, reason) {
    if (w._dead || w._done) return;
    w._dead = true;

    clearWatchdog(w);
    const outcome = w._timedOut
      ? decodeTestRunResult(timeoutResult(timeoutMs))
      : makeGenericError(reason);

    if (w._activeTest) {
      deliverPoolResult(
        testResult(w._activeTest, outcome, millisecondsToDuration(0)),
      );
      w._activeTest = null;
    }

    // Watchdog kills are the test's fault, not the worker's — don't count
    // them, or sync-hang storms would exhaust the cap into the main-thread
    // fallback where a hang cannot be interrupted.
    if (!w._timedOut) {
      workerFailures++;
    }
    if (workerFailures >= maxWorkerFailures) {
      const remaining = queue.splice(0, queue.length);
      if (remaining.length > 0) {
        startWithPromises(
          groupByModule(remaining),
          packageName,
          checkResults,
          timeoutMs,
          workers,
        );
      }
    } else if (queue.length > 0) {
      spawnWorker();
    }
  }

  function spawnWorker() {
    const w = new Worker(workerUrl, { type: "module" });

    w.on("message", (msg) => {
      if (msg.type === "ready") {
        sendNext(w);
      } else if (msg.type === "result") {
        clearWatchdog(w);
        const test = w._activeTest;
        w._activeTest = null;
        if (test) {
          deliverPoolResult(
            testResult(
              test,
              decodeTestRunResult(msg.result),
              millisecondsToDuration(msg.durationMs),
            ),
          );
        }
        if (msg.result?.failureKind?.type === "timeout") {
          // Promise.race cannot cancel the losing test; it is still running
          // inside this worker. Recycle the worker so its side effects cannot
          // interfere with later tests. Deliberate, so it does not count
          // toward the worker failure cap.
          recycleWorker(w);
        } else {
          sendNext(w);
        }
      }
    });

    w.on("error", (err) => {
      handleWorkerDeath(w, "Worker crashed: " + (err.message || String(err)));
    });

    w.on("exit", (code) => {
      if (code !== 0) {
        handleWorkerDeath(w, "Worker exited unexpectedly with code " + code);
      }
    });
  }

  for (let i = 0; i < workerCount; i++) {
    spawnWorker();
  }
}

export function receivePoolResult(callback) {
  if (poolResultQueue.length > 0) {
    callback(poolResultQueue.shift());
  } else {
    poolWaitingCallback = callback;
  }
}
