import { parentPort } from "node:worker_threads";

import {
  genericError,
  runTest as runTestCommon,
  timeoutResult,
} from "./unitest_common_ffi.mjs";

const TIMED_OUT = Symbol("unitest_timed_out");

// Race each test against its own timeout.
async function runTest({
  moduleUrl,
  fnName,
  checkResults,
  timeoutMs,
  moduleName,
}) {
  try {
    if (!timeoutMs || timeoutMs <= 0) {
      return await runTestCommon(moduleUrl, fnName, checkResults, moduleName);
    }

    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => resolve(TIMED_OUT), timeoutMs);
    });
    const result = await Promise.race([
      runTestCommon(moduleUrl, fnName, checkResults, moduleName),
      timeout,
    ]);
    clearTimeout(timer);

    if (result === TIMED_OUT) {
      return timeoutResult(timeoutMs);
    }
    return result;
  } catch (error) {
    return genericError(
      "Worker test execution failed: " + (error.message || String(error)),
    );
  }
}

parentPort.on("message", async (msg) => {
  if (msg.type === "run") {
    const start = performance.now();
    const result = await runTest(msg);
    const durationMs = Math.round(performance.now() - start);
    parentPort.postMessage({
      type: "result",
      durationMs,
      result,
    });
  }
});

parentPort.postMessage({ type: "ready" });
