import { inspect as stringInspect } from "../gleam_stdlib/gleam/string.mjs";
import { Result$isError, toList } from "./gleam.mjs";
import {
  TestRunResult$Ran,
  TestRunResult$RuntimeSkip,
  TestRunResult$RunError,
} from "./unitest/internal/runner.mjs";
import {
  AssertedExpr$AssertedExpr,
  AssertKind$BinaryOperator,
  AssertKind$FunctionCall,
  AssertKind$OtherExpression,
  ExprKind$Expression,
  ExprKind$Literal,
  ExprKind$Unevaluated,
  PanicKind$Assert,
  PanicKind$Generic,
  PanicKind$LetAssert,
  PanicKind$Panic,
  PanicKind$Todo,
  TestFailure$TestFailure,
} from "./unitest/internal/test_failure.mjs";

const runtime =
  typeof Deno !== "undefined"
    ? "deno"
    : typeof process !== "undefined"
      ? "node"
      : null;

export function autoSeed() {
  return Date.now() % 1000000;
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

const SKIP_SYMBOL = Symbol.for("gleam_unitest_skip");

export function skip() {
  throw { [SKIP_SYMBOL]: true };
}

function isSkipException(e) {
  return e && typeof e === "object" && SKIP_SYMBOL in e;
}

async function runTest(test, packageName) {
  try {
    const modulePath = test.module;
    const path = `../${packageName}/${modulePath}.mjs`;
    const mod = await import(path);
    const fnName = test.name;

    if (typeof mod[fnName] === "function") {
      const result = await mod[fnName]();
      if (Result$isError(result)) {
        const reason = result[0];
        const message = "Test returned Error: " + stringInspect(reason);
        const error = TestFailure$TestFailure(
          message,
          "",
          "",
          "",
          0,
          PanicKind$Generic(),
        );
        return TestRunResult$RunError(error);
      }

      return TestRunResult$Ran();
    } else {
      const error = parseErrorFromTest(
        new Error(`Function ${fnName} not found in module ${modulePath}`),
      );
      return TestRunResult$RunError(error);
    }
  } catch (e) {
    if (isSkipException(e)) {
      return TestRunResult$RuntimeSkip();
    }
    const error = parseErrorFromTest(e);
    return TestRunResult$RunError(error);
  }
}

export function runTestAsync(test, packageName, next) {
  runTest(test, packageName).then((result) => {
    next(result);
  });
}

function parseErrorFromTest(error) {
  if (error instanceof globalThis.Error && error.gleam_error) {
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

  if (
    errorMessage.includes("Cannot find module") ||
    errorMessage.includes("Module not found") ||
    errorMessage.includes("does not provide an export")
  ) {
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

  if (error instanceof TypeError) {
    const undefMatch = errorMessage.match(/(\w+) is not a function/);
    if (undefMatch) {
      return `Undefined function: ${undefMatch[1]}`;
    }
  }

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
