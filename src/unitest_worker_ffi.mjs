import { parentPort } from "node:worker_threads";

import { genericError, runTestRaw } from "./unitest_common_ffi.mjs";

parentPort.on("message", async (msg) => {
  if (msg.type === "run") {
    const start = Date.now();
    let result;
    try {
      result = await runTestRaw(msg.moduleUrl, msg.fnName, msg.checkResults);
    } catch {
      result = genericError("Worker test execution failed");
    }
    const durationMs = Date.now() - start;
    parentPort.postMessage({
      type: "result",
      testIndex: msg.testIndex,
      durationMs,
      result,
    });
  }
});

parentPort.postMessage({ type: "ready" });
