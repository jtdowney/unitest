import { parentPort } from "node:worker_threads";

import { runTestRaw } from "./unitest_common_ffi.mjs";

parentPort.on("message", async (msg) => {
  if (msg.type === "run") {
    const start = Date.now();
    let result;
    try {
      result = await runTestRaw(msg.moduleUrl, msg.fnName, msg.checkResults);
    } catch {
      result = {
        kind: "error",
        message: "Worker test execution failed",
        file: "",
        module: "",
        fn: "",
        line: 0,
        panicKind: { type: "generic" },
      };
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
