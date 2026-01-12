import { inspect as stringInspect } from "../gleam_stdlib/gleam/string.mjs";
import { toList } from "./gleam.mjs";

const runtime =
  typeof Deno !== "undefined"
    ? "deno"
    : typeof process !== "undefined"
      ? "node"
      : null;

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
import {
  TestFailure$TestFailure,
  PanicKind$Assert,
  PanicKind$Panic,
  PanicKind$Todo,
  PanicKind$LetAssert,
  PanicKind$Generic,
  AssertKind$BinaryOperator,
  AssertKind$FunctionCall,
  AssertKind$OtherExpression,
  AssertedExpr$AssertedExpr,
  ExprKind$Literal,
  ExprKind$Expression,
  ExprKind$Unevaluated,
} from "./unitest/internal/test_failure.mjs";

export function autoSeed() {
  return Date.now() % 1000000;
}

function parseErrorFromTest(error) {
  if (error instanceof Error && error.gleam_error) {
    const message = error.message || "Unknown error";
    const file = error.file || "";
    const module = error.module || "";
    const fn = error.function || "";
    const line = error.line || 0;

    let kind;
    switch (error.gleam_error) {
      case "assert":
        kind = PanicKind$Assert(
          error.start || 0,
          error.end || 0,
          error.expression_start || 0,
          buildAssertKind(error),
        );
        break;
      case "panic":
        kind = PanicKind$Panic();
        break;
      case "todo":
        kind = PanicKind$Todo();
        break;
      case "let_assert":
        kind = PanicKind$LetAssert(
          error.start || 0,
          error.end || 0,
          stringInspect(error.value),
        );
        break;
      default:
        kind = PanicKind$Generic();
    }

    return TestFailure$TestFailure(message, file, module, fn, line, kind);
  }

  const message = error.message || String(error);
  return TestFailure$TestFailure(message, "", "", "", 0, PanicKind$Generic());
}

function buildAssertKind(error) {
  switch (error.kind) {
    case "binary_operator":
      return AssertKind$BinaryOperator(
        String(error.operator || "=="),
        buildAssertedExpr(error.left),
        buildAssertedExpr(error.right),
      );
    case "function_call": {
      const args = (error.arguments || []).map(buildAssertedExpr);
      return AssertKind$FunctionCall(toList(args));
    }
    case "other_expression":
      return AssertKind$OtherExpression(buildAssertedExpr(error.expression));
    default:
      return AssertKind$OtherExpression(
        AssertedExpr$AssertedExpr(0, 0, ExprKind$Unevaluated()),
      );
  }
}

function buildAssertedExpr(expr) {
  if (!expr) {
    return AssertedExpr$AssertedExpr(0, 0, ExprKind$Unevaluated());
  }

  const start = expr.start || 0;
  const end = expr.end || 0;

  let kind;
  switch (expr.kind) {
    case "literal":
      kind = ExprKind$Literal(stringInspect(expr.value));
      break;
    case "expression":
      kind = ExprKind$Expression(stringInspect(expr.value));
      break;
    default:
      kind = ExprKind$Unevaluated();
  }

  return AssertedExpr$AssertedExpr(start, end, kind);
}

function exit(code) {
  if (runtime === "node") {
    process.exit(code);
  } else if (runtime === "deno") {
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
    if (runtime === "deno") {
      content = await Deno.readTextFile("gleam.toml");
    } else if (runtime === "node") {
      const fs = await import("node:fs/promises");
      content = await fs.readFile("gleam.toml", "utf-8");
    } else {
      throw new Error("Unsupported JavaScript runtime");
    }

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
  if (runtime === "node") {
    process.stdout.write(s);
  } else if (runtime === "deno") {
    Deno.stdout.writeSync(new TextEncoder().encode(s));
  }
}

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
          const error = parseErrorFromTest(
            new Error(`Function ${fnName} not found in module ${modulePath}`),
          );
          failed++;
          print(outcomeChar(Outcome$Failed(error), useColor));
          failures.push(
            FailedTest$FailedTest(test, error, testEnd - testStart),
          );
        }
      } catch (e) {
        const testEnd = Date.now();
        const error = parseErrorFromTest(e);
        failed++;
        print(outcomeChar(Outcome$Failed(error), useColor));
        failures.push(FailedTest$FailedTest(test, error, testEnd - testStart));
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
