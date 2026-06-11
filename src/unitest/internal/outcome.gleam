import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import unitest
import unitest/internal/test_failure

pub fn from_dynamic(raw: Dynamic) -> unitest.Outcome {
  let decoder = {
    use tag <- decode.field("kind", decode.string)
    case tag {
      "ran" -> decode.success(unitest.Passed)
      "skip" -> decode.success(unitest.Skipped)
      "error" -> {
        use failure <- decode.then(decode_test_failure())
        decode.success(unitest.Failed(failure))
      }
      _ -> decode.success(generic_outcome("Unknown result kind"))
    }
  }

  case decode.run(raw, decoder) {
    Ok(result) -> result
    Error(_) -> generic_outcome("Failed to decode test result")
  }
}

fn generic_outcome(message: String) -> unitest.Outcome {
  unitest.Failed(test_failure.TestFailure(
    message:,
    file: "",
    line: 0,
    kind: test_failure.Generic,
  ))
}

fn decode_test_failure() -> decode.Decoder(test_failure.TestFailure) {
  use message <- decode.optional_field("message", "", decode.string)
  use file <- decode.optional_field("file", "", decode.string)
  use line <- decode.optional_field("line", 0, decode.int)
  use kind <- decode.optional_field(
    "failureKind",
    test_failure.Generic,
    decode_failure_kind(),
  )
  decode.success(test_failure.TestFailure(message:, file:, line:, kind:))
}

const default_asserted_expr = test_failure.AssertedExpr(
  start: 0,
  end: 0,
  kind: test_failure.Unevaluated,
)

fn decode_failure_kind() -> decode.Decoder(test_failure.FailureKind) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "assert" -> {
      use start <- decode.optional_field("start", 0, decode.int)
      use end <- decode.optional_field("end", 0, decode.int)
      use kind <- decode.optional_field(
        "assertKind",
        test_failure.OtherExpression(default_asserted_expr),
        decode_assert_kind(),
      )
      decode.success(test_failure.Assert(start:, end:, kind:))
    }
    "panic" -> decode.success(test_failure.Panic)
    "todo" -> decode.success(test_failure.Todo)
    "let_assert" -> {
      use start <- decode.optional_field("start", 0, decode.int)
      use end <- decode.optional_field("end", 0, decode.int)
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(test_failure.LetAssert(start:, end:, value:))
    }
    "timeout" -> {
      use timeout_ms <- decode.optional_field("timeout_ms", 0, decode.int)
      decode.success(test_failure.Timeout(timeout_ms:))
    }
    "crashed" -> {
      use reason <- decode.optional_field("reason", "", decode.string)
      use stack <- decode.optional_field(
        "stack",
        [],
        decode.list(decode_stack_frame()),
      )
      decode.success(test_failure.Crashed(reason:, stack:))
    }
    "undef" -> {
      use module <- decode.optional_field("module", "", decode.string)
      use function <- decode.optional_field("function", "", decode.string)
      use arity <- decode.optional_field("arity", 0, decode.int)
      decode.success(test_failure.Undef(module:, function:, arity:))
    }
    _ -> decode.success(test_failure.Generic)
  }
}

fn decode_assert_kind() -> decode.Decoder(test_failure.AssertKind) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "binary_operator" -> {
      use operator <- decode.optional_field("operator", "==", decode.string)
      use left <- decode.optional_field(
        "left",
        default_asserted_expr,
        decode_asserted_expr_value(),
      )
      use right <- decode.optional_field(
        "right",
        default_asserted_expr,
        decode_asserted_expr_value(),
      )
      decode.success(test_failure.BinaryOperator(operator:, left:, right:))
    }
    "function_call" -> {
      use args <- decode.optional_field(
        "arguments",
        [],
        decode.list(decode_asserted_expr_value()),
      )
      decode.success(test_failure.FunctionCall(args))
    }
    "other_expression" -> {
      use expr <- decode.optional_field(
        "expression",
        default_asserted_expr,
        decode_asserted_expr_value(),
      )
      decode.success(test_failure.OtherExpression(expr))
    }
    _ -> decode.success(test_failure.OtherExpression(default_asserted_expr))
  }
}

fn decode_stack_frame() -> decode.Decoder(test_failure.StackFrame) {
  use module <- decode.optional_field("module", "", decode.string)
  use function <- decode.optional_field("function", "", decode.string)
  use arity <- decode.optional_field("arity", 0, decode.int)
  use file <- decode.optional_field("file", "", decode.string)
  use line <- decode.optional_field("line", 0, decode.int)
  decode.success(test_failure.StackFrame(
    module:,
    function:,
    arity:,
    file:,
    line:,
  ))
}

fn decode_asserted_expr_value() -> decode.Decoder(test_failure.AssertedExpr) {
  use start <- decode.optional_field("start", 0, decode.int)
  use end <- decode.optional_field("end", 0, decode.int)
  use kind <- decode.then(decode_expr_kind())
  decode.success(test_failure.AssertedExpr(start:, end:, kind:))
}

fn decode_expr_kind() -> decode.Decoder(test_failure.ExprKind) {
  use tag <- decode.optional_field("kind", "", decode.string)
  case tag {
    "literal" -> {
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(test_failure.Literal(value))
    }
    "expression" -> {
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(test_failure.Expression(value))
    }
    _ -> decode.success(test_failure.Unevaluated)
  }
}
