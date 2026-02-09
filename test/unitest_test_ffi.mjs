import {
  execute_sequential as executeSequential,
  execute_pooled as executePooled,
} from "./unitest/internal/runner.mjs";

export function executeSyncSequentialJs(
  plan,
  seed,
  platform,
  onResult,
  callback,
) {
  return new Promise((resolve) => {
    executeSequential(plan, seed, platform, onResult, (result) => {
      resolve(callback(result));
    });
  });
}

export function executeSyncPooledJs(
  plan,
  seed,
  workers,
  platform,
  onResult,
  callback,
) {
  return new Promise((resolve) => {
    executePooled(plan, seed, workers, platform, onResult, (result) => {
      resolve(callback(result));
    });
  });
}

let testPoolResultQueue = [];
let testPoolWaitingCallback = null;

export function sendPoolResult(poolResult) {
  if (testPoolWaitingCallback) {
    const cb = testPoolWaitingCallback;
    testPoolWaitingCallback = null;
    cb(poolResult);
  } else {
    testPoolResultQueue.push(poolResult);
  }
}

export function receivePoolResultTest(callback) {
  if (testPoolResultQueue.length > 0) {
    callback(testPoolResultQueue.shift());
  } else {
    testPoolWaitingCallback = callback;
  }
}
