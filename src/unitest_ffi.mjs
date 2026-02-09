import { SKIP_SYMBOL, runTestRaw } from "./unitest_common_ffi.mjs";
import {
  decode_test_run_result as decodeTestRunResult,
  wrap_pool_result as wrapPoolResult,
  make_crash_error as makeCrashError,
} from "./unitest/internal/js_decode.mjs";

function formatError(err) {
  return err == null ? String(err) : err.message || String(err);
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
  return Date.now();
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
  const raw = await runTestRaw(moduleUrl, test.name, checkResults);
  return decodeTestRunResult(raw);
}

export function runTestAsync(test, packageName, checkResults, next) {
  runTest(test, packageName, checkResults)
    .then((result) => {
      next(result);
    })
    .catch((err) => {
      next(makeCrashError(formatError(err)));
    });
}

let poolResultQueue = [];
let poolWaitingCallback = null;

function deliverPoolResult(pr) {
  if (poolWaitingCallback) {
    const cb = poolWaitingCallback;
    poolWaitingCallback = null;
    cb(pr);
  } else {
    poolResultQueue.push(pr);
  }
}

export function startModulePool(
  moduleGroups,
  packageName,
  checkResults,
  workers,
) {
  poolResultQueue = [];
  poolWaitingCallback = null;

  if (nodeWorkerThreads) {
    try {
      startWithWorkerThreads(moduleGroups, packageName, checkResults, workers);
    } catch {
      startWithPromises(moduleGroups, packageName, checkResults, workers);
    }
  } else {
    startWithPromises(moduleGroups, packageName, checkResults, workers);
  }
}

function startWithPromises(moduleGroups, packageName, checkResults, workers) {
  const queue = moduleGroups.toArray().map((g) => g.toArray());
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
          runTest(test, packageName, checkResults)
            .then((result) => {
              deliverPoolResult(wrapPoolResult(test, result, nowMs() - start));
            })
            .catch((err) => {
              const msg = formatError(err);
              deliverPoolResult(
                wrapPoolResult(test, makeCrashError(msg), nowMs() - start),
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

function startWithWorkerThreads(
  moduleGroups,
  packageName,
  checkResults,
  workers,
) {
  const { Worker } = nodeWorkerThreads;
  const queue = moduleGroups.toArray().map((g) => g.toArray());
  const limit = Math.max(1, workers | 0);
  const workerCount = Math.min(limit, queue.length);

  if (workerCount === 0) return;

  const workerUrl = new URL("./unitest_worker_ffi.mjs", import.meta.url);

  let dispatchIndex = 0;
  const allTests = queue.flat();
  const batches = [];
  let globalIdx = 0;
  for (const group of queue) {
    batches.push({ tests: group, globalStartIndex: globalIdx });
    globalIdx += group.length;
  }

  let workerFailures = 0;
  const maxWorkerFailures = 3;

  function dispatch(w) {
    if (dispatchIndex >= batches.length) {
      w.terminate();
      return;
    }
    const batchIdx = dispatchIndex++;
    const batch = batches[batchIdx];
    w._pendingTests = new Set(batch.tests);
    w._pendingCount = batch.tests.length;

    for (let i = 0; i < batch.tests.length; i++) {
      const test = batch.tests[i];
      w.postMessage({
        type: "run",
        testIndex: batch.globalStartIndex + i,
        moduleUrl: new URL(
          `../${packageName}/${test.module}.mjs`,
          import.meta.url,
        ).href,
        fnName: test.name,
        checkResults,
      });
    }
  }

  function handleWorkerDeath(w, reason) {
    if (w._dead) return;
    w._dead = true;

    if (w._pendingTests && w._pendingTests.size > 0) {
      for (const test of w._pendingTests) {
        deliverPoolResult(wrapPoolResult(test, makeCrashError(reason), 0));
      }
      w._pendingTests = null;
    }

    workerFailures++;
    if (workerFailures >= maxWorkerFailures) {
      const remaining = batches.slice(dispatchIndex);
      dispatchIndex = batches.length;
      if (remaining.length > 0) {
        const fakeGroups = {
          toArray: () => remaining.map((b) => ({ toArray: () => b.tests })),
        };
        startWithPromises(fakeGroups, packageName, checkResults, workers);
      }
    } else if (dispatchIndex < batches.length) {
      spawnWorker();
    }
  }

  function spawnWorker() {
    const w = new Worker(workerUrl, { type: "module" });

    w.on("message", (msg) => {
      if (msg.type === "ready") {
        dispatch(w);
      } else if (msg.type === "result") {
        const test = allTests[msg.testIndex];
        if (w._pendingTests) {
          w._pendingTests.delete(test);
        }
        deliverPoolResult(
          wrapPoolResult(test, decodeTestRunResult(msg.result), msg.durationMs),
        );
        w._pendingCount -= 1;
        if (w._pendingCount === 0) {
          dispatch(w);
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
