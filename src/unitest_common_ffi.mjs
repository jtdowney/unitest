import { inspect as stringInspect } from "../gleam_stdlib/gleam/string.mjs";
import { Result$isError } from "./gleam.mjs";

export const SKIP_SYMBOL = Symbol.for("gleam_unitest_skip");

export function isSkipException(e) {
  return e && typeof e === "object" && SKIP_SYMBOL in e;
}

export function formatGenericError(error) {
  if (error == null) {
    return "";
  }

  const errorMessage = error.message || String(error);
  const code = error.code;

  if (
    code === "ERR_MODULE_NOT_FOUND" ||
    code === "MODULE_NOT_FOUND" ||
    code === "ERR_PACKAGE_PATH_NOT_EXPORTED"
  ) {
    if (code === "ERR_PACKAGE_PATH_NOT_EXPORTED") {
      const exportMatch = errorMessage.match(
        /does not provide an export named ['"]([^'"]+)['"]/,
      );
      if (exportMatch) {
        return `Undefined function: ${exportMatch[1]}`;
      }
    }
    const moduleMatch = errorMessage.match(
      /Cannot find module ['"]([^'"]+)['"]/,
    );
    if (moduleMatch) {
      return `Module not found: ${moduleMatch[1]}`;
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

function serializeAssertedExpr(expr) {
  if (!expr) {
    return { start: 0, end: 0, kind: "unevaluated" };
  }

  let serializedKind;
  switch (expr.kind) {
    case "literal":
      serializedKind = { kind: "literal", value: stringInspect(expr.value) };
      break;
    case "expression":
      serializedKind = { kind: "expression", value: stringInspect(expr.value) };
      break;
    default:
      serializedKind = { kind: "unevaluated" };
  }

  return {
    start: expr.start || 0,
    end: expr.end || 0,
    ...serializedKind,
  };
}

function serializeAssertKind(error) {
  switch (error.kind) {
    case "binary_operator":
      return {
        type: "binary_operator",
        operator: String(error.operator || "=="),
        left: serializeAssertedExpr(error.left),
        right: serializeAssertedExpr(error.right),
      };
    case "function_call":
      return {
        type: "function_call",
        arguments: (error.arguments || []).map(serializeAssertedExpr),
      };
    case "other_expression":
      return {
        type: "other_expression",
        expression: serializeAssertedExpr(error.expression),
      };
    default:
      return {
        type: "other_expression",
        expression: { start: 0, end: 0, kind: "unevaluated" },
      };
  }
}

function serializeError(e) {
  if (e instanceof globalThis.Error && e.gleam_error) {
    const base = {
      message: e.message || "Unknown error",
      file: e.file || "",
      module: e.module || "",
      fn: e.function || "",
      line: e.line || 0,
    };

    switch (e.gleam_error) {
      case "assert":
        base.panicKind = {
          type: "assert",
          start: e.start || 0,
          end: e.end || 0,
          expressionStart: e.expression_start || 0,
          assertKind: serializeAssertKind(e),
        };
        break;
      case "panic":
        base.panicKind = { type: "panic" };
        break;
      case "todo":
        base.panicKind = { type: "todo" };
        break;
      case "let_assert":
        base.panicKind = {
          type: "let_assert",
          start: e.start || 0,
          end: e.end || 0,
          value: stringInspect(e.value),
        };
        break;
      default:
        base.panicKind = { type: "generic" };
    }
    return base;
  }

  return {
    message: formatGenericError(e),
    file: "",
    module: "",
    fn: "",
    line: 0,
    panicKind: { type: "generic" },
  };
}

export async function runTestRaw(moduleUrl, fnName, checkResults) {
  try {
    const mod = await import(moduleUrl);
    if (typeof mod[fnName] === "function") {
      const result = await mod[fnName]();
      if (checkResults && Result$isError(result)) {
        const reason = result[0];
        const message = "Test returned Error: " + stringInspect(reason);
        return {
          kind: "error",
          message,
          file: "",
          module: "",
          fn: "",
          line: 0,
          panicKind: { type: "generic" },
        };
      }
      return { kind: "ran" };
    } else {
      return {
        kind: "error",
        message: "Function " + fnName + " not found in module",
        file: "",
        module: "",
        fn: "",
        line: 0,
        panicKind: { type: "generic" },
      };
    }
  } catch (e) {
    if (isSkipException(e)) {
      return { kind: "skip" };
    } else {
      return { kind: "error", ...serializeError(e) };
    }
  }
}
