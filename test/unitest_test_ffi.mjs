import { execute } from "./unitest/internal/runner.mjs";

export function executeSyncJs(plan, seed, platform, onResult, callback) {
  return new Promise((resolve) => {
    execute(plan, seed, platform, onResult, (result) => {
      resolve(callback(result));
    });
  });
}
