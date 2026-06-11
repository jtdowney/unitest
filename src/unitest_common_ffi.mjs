import { inspect as stringInspect } from "../gleam_stdlib/gleam/string.mjs";
import { Result$isError } from "./gleam.mjs";

export const SKIP_SYMBOL = Symbol.for("gleam_unitest_skip");

function isSkipException(e) {
  return e && typeof e === "object" && SKIP_SYMBOL in e;
}

export function genericError(message) {
  return { kind: "error", message };
}

export function timeoutResult(timeoutMs) {
  return {
    kind: "error",
    failureKind: { type: "timeout", timeout_ms: timeoutMs },
  };
}

function translateError(error) {
  if (error == null) {
    return { recognized: true, message: "" };
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
        return {
          recognized: true,
          message: `Undefined function: ${exportMatch[1]}`,
        };
      }
    }
    const moduleMatch = errorMessage.match(
      /Cannot find module ['"]([^'"]+)['"]/,
    );
    if (moduleMatch) {
      return {
        recognized: true,
        message: `Module not found: ${moduleMatch[1]}`,
      };
    }
    return { recognized: true, message: errorMessage };
  }

  if (error instanceof TypeError) {
    const undefMatch = errorMessage.match(/(\w+) is not a function/);
    if (undefMatch) {
      return {
        recognized: true,
        message: `Undefined function: ${undefMatch[1]}`,
      };
    }
  }

  if (error instanceof ReferenceError) {
    const refMatch = errorMessage.match(/(\w+) is not defined/);
    if (refMatch) {
      return { recognized: true, message: `Undefined: ${refMatch[1]}` };
    }
  }

  return { recognized: false, message: errorMessage };
}

export function parseStack(error) {
  if (!error || typeof error.stack !== "string") {
    return [];
  }

  const frames = [];
  for (const line of error.stack.split("\n")) {
    const frame = parseStackLine(line);
    if (frame) {
      frames.push(frame);
    }
  }
  return frames;
}

function parseStackLine(line) {
  const text = line.trim();
  if (!text.startsWith("at ")) {
    return null;
  }

  let functionName = "";
  let location = text.slice(3);
  const named = text.match(/^at (.+?) \((.+)\)$/);
  if (named) {
    functionName = named[1];
    location = named[2];
  }

  const locationMatch = location.match(/^(.*):(\d+):(\d+)$/);
  if (!locationMatch) {
    return null;
  }

  const file = locationMatch[1].replace(/^file:\/\//, "");
  const base = file.split(/[\\/]/).pop() || file;
  const name = functionName
    .replace(/^(async|new) /, "")
    .split(".")
    .pop();
  return {
    module: base.replace(/\.[^.]+$/, ""),
    function: name || "<anonymous>",
    arity: 0,
    file,
    line: Number(locationMatch[2]),
  };
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
      line: e.line || 0,
    };

    switch (e.gleam_error) {
      case "assert":
        base.failureKind = {
          type: "assert",
          start: e.start || 0,
          end: e.end || 0,
          assertKind: serializeAssertKind(e),
        };
        break;
      case "panic":
        base.failureKind = { type: "panic" };
        break;
      case "todo":
        base.failureKind = { type: "todo" };
        break;
      case "let_assert":
        base.failureKind = {
          type: "let_assert",
          start: e.start || 0,
          end: e.end || 0,
          value: stringInspect(e.value),
        };
        break;
    }
    return base;
  }

  const { recognized, message } = translateError(e);
  if (recognized) {
    return { message };
  }

  return {
    failureKind: { type: "crashed", reason: message, stack: parseStack(e) },
  };
}

export async function runTest(
  moduleUrl,
  fnName,
  checkResults,
  moduleName = "",
) {
  try {
    const mod = await import(moduleUrl);
    if (typeof mod[fnName] === "function") {
      const result = await mod[fnName]();
      if (checkResults && Result$isError(result)) {
        const reason = result[0];
        return genericError(`Test returned Error: ${stringInspect(reason)}`);
      }
      return { kind: "ran" };
    } else {
      return {
        kind: "error",
        failureKind: {
          type: "undef",
          module: moduleName,
          function: fnName,
          arity: 0,
        },
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
