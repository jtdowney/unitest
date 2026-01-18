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
  Outcome$Failed,
  Outcome$Passed,
  Outcome$Skipped,
  PlanItem$Run$0,
  PlanItem$isRun,
  PlanItem$Skip$0,
  Report$Report,
  ExecuteResult$ExecuteResult,
  TestResult$TestResult,
} from "./unitest/internal/runner.mjs";
import { Reporter$isDotReporter } from "./unitest/internal/cli.mjs";
import { render_table as renderTable } from "./unitest/internal/format_table.mjs";
import {
  new$ as spinnerNew,
  start as spinnerStart,
  stop as spinnerStop,
  set_text as spinnerSetText,
  with_colour as spinnerWithColour,
} from "../spinner/spinner.mjs";
import { cyan as ansiCyan } from "../gleam_community_ansi/gleam_community/ansi.mjs";
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

  const message = formatGenericError(error);
  return TestFailure$TestFailure(message, "", "", "", 0, PanicKind$Generic());
}

function formatGenericError(error) {
  const errorMessage = error.message || String(error);

  // Module not found errors
  if (
    errorMessage.includes("Cannot find module") ||
    errorMessage.includes("Module not found") ||
    errorMessage.includes("does not provide an export")
  ) {
    // Extract module name from error message if possible
    const moduleMatch = errorMessage.match(
      /Cannot find module ['"]([^'"]+)['"]/,
    );
    if (moduleMatch) {
      return `Module not found: ${moduleMatch[1]}`;
    }
    const exportMatch = errorMessage.match(
      /does not provide an export named ['"]([^'"]+)['"]/,
    );
    if (exportMatch) {
      return `Undefined function: ${exportMatch[1]}`;
    }
    return errorMessage;
  }

  // TypeError for calling undefined as function
  if (error instanceof TypeError) {
    const undefMatch = errorMessage.match(/(\w+) is not a function/);
    if (undefMatch) {
      return `Undefined function: ${undefMatch[1]}`;
    }
  }

  // ReferenceError for undefined variables
  if (error instanceof ReferenceError) {
    const refMatch = errorMessage.match(/(\w+) is not defined/);
    if (refMatch) {
      return `Undefined: ${refMatch[1]}`;
    }
  }

  return errorMessage;
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

export async function execute_and_finish_js(plan, seed, useColor, reporter) {
  const startMs = Date.now();
  const packageName = await getPackageName();
  const isDotReporter = Reporter$isDotReporter(reporter);

  let passed = 0;
  let failed = 0;
  let skipped = 0;
  const failures = [];
  const results = [];

  const planArray = plan.toArray();
  const total = planArray.length;

  const sp = isDotReporter
    ? null
    : spinnerStart(spinnerWithColour(spinnerNew("Running tests..."), ansiCyan));

  function reportProgress(outcome, current) {
    if (isDotReporter) {
      print(outcomeChar(outcome, useColor));
    } else {
      spinnerSetText(sp, `Running tests... ${current}/${total}`);
    }
  }

  function recordResult(test, outcome, duration, isFailure) {
    const result = TestResult$TestResult(test, outcome, duration);
    results.push(result);
    if (isFailure) {
      failures.push(result);
    }
  }

  const yieldToEventLoop = () =>
    new Promise((r) =>
      typeof setImmediate !== "undefined" ? setImmediate(r) : setTimeout(r, 0),
    );

  let current = 0;
  for (const item of planArray) {
    current++;

    // Yield periodically to allow spinner's setInterval to fire
    if (!isDotReporter && current % 5 === 0) {
      await yieldToEventLoop();
    }

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
          const duration = Date.now() - testStart;
          passed++;
          const outcome = Outcome$Passed();
          recordResult(test, outcome, duration, false);
          reportProgress(outcome, current);
        } else {
          const duration = Date.now() - testStart;
          const error = parseErrorFromTest(
            new Error(`Function ${fnName} not found in module ${modulePath}`),
          );
          failed++;
          const outcome = Outcome$Failed(error);
          recordResult(test, outcome, duration, true);
          reportProgress(outcome, current);
        }
      } catch (e) {
        const duration = Date.now() - testStart;
        const error = parseErrorFromTest(e);
        failed++;
        const outcome = Outcome$Failed(error);
        recordResult(test, outcome, duration, true);
        reportProgress(outcome, current);
      }
    } else {
      const test = PlanItem$Skip$0(item);
      skipped++;
      const outcome = Outcome$Skipped();
      recordResult(test, outcome, 0, false);
      reportProgress(outcome, current);
    }
  }

  if (sp) {
    spinnerStop(sp);
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

  if (!isDotReporter) {
    print(renderTable(toList(results), useColor));
  }

  console.log(renderSummary(report, useColor));

  if (failed > 0) {
    exit(1);
  }
}
