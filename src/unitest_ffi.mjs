import { toList } from "./gleam.mjs";
import {
  outcome_char as outcomeChar,
  render_summary as renderSummary,
  FailedTest$FailedTest,
  Outcome$Failed,
  Outcome$Passed,
  Outcome$Skipped,
  PlanItem$Run$0,
  PlanItem$isRun,
  Report$Report,
} from "./unitest/internal/runner.mjs";

export function autoSeed() {
  return Date.now() % 1000000;
}

function exit(code) {
  if (typeof process !== "undefined") {
    process.exit(code);
  } else if (typeof Deno !== "undefined") {
    Deno.exit(code);
  }
}

let cachedPackageName = null;

async function getPackageName() {
  if (cachedPackageName) {
    return cachedPackageName;
  }

  try {
    let content;
    if (typeof Deno !== "undefined") {
      content = await Deno.readTextFile("gleam.toml");
    } else if (typeof process !== "undefined") {
      const fs = await import("node:fs/promises");
      content = await fs.readFile("gleam.toml", "utf-8");
    } else {
      throw new Error("Unsupported JavaScript runtime");
    }

    // Parse name from gleam.toml (simple regex for name = "...")
    const match = content.match(/^name\s*=\s*"([^"]+)"/m);
    if (match) {
      cachedPackageName = match[1];
      return cachedPackageName;
    }
    throw new Error("Could not find package name in gleam.toml");
  } catch (e) {
    throw new Error(`Failed to read package name: ${e.message}`);
  }
}

function print(s) {
  if (typeof process !== "undefined") {
    process.stdout.write(s);
  } else if (typeof Deno !== "undefined") {
    Deno.stdout.writeSync(new TextEncoder().encode(s));
  }
}

// JS-specific execute and finish function - handles async test running,
// prints summary, and exits with appropriate code.
// This is async but the runtime handles the Promise at top level.
export async function execute_and_finish_js(plan, seed, useColor) {
  const startMs = Date.now();
  const packageName = await getPackageName();

  let passed = 0;
  let failed = 0;
  let skipped = 0;
  let failures = [];

  const planArray = plan.toArray();

  for (const item of planArray) {
    if (PlanItem$isRun(item)) {
      const test = PlanItem$Run$0(item);
      const testStart = Date.now();

      try {
        const modulePath = test.module;
        const path = `../${packageName}/${modulePath}.mjs`;
        const mod = await import(path);
        const fnName = test.name;

        if (typeof mod[fnName] === "function") {
          await mod[fnName]();
          passed++;
          print(outcomeChar(Outcome$Passed(), useColor));
        } else {
          const testEnd = Date.now();
          const reason = `Function ${fnName} not found in module ${modulePath}`;
          failed++;
          print(outcomeChar(Outcome$Failed(reason), useColor));
          failures.push(
            FailedTest$FailedTest(test, reason, testEnd - testStart),
          );
        }
      } catch (e) {
        const testEnd = Date.now();
        const reason = e.message || String(e);
        failed++;
        print(outcomeChar(Outcome$Failed(reason), useColor));
        failures.push(FailedTest$FailedTest(test, reason, testEnd - testStart));
      }
    } else {
      skipped++;
      print(outcomeChar(Outcome$Skipped(), useColor));
    }
  }

  const endMs = Date.now();

  const report = Report$Report(
    passed,
    failed,
    skipped,
    toList(failures),
    seed,
    endMs - startMs,
  );

  const summary = renderSummary(report, useColor);
  console.log(summary);

  if (failed > 0) {
    exit(1);
  }
}
