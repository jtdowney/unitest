import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import unitest/internal/discover.{type Test}
import unitest/internal/runner.{type PoolResult, type TestRunResult}
import unitest/internal/test_failure.{
  type AssertKind, type AssertedExpr, type ExprKind, type PanicKind,
  type TestFailure,
}

pub fn decode_test_run_result(raw: Dynamic) -> TestRunResult {
  let decoder = {
    use tag <- decode.field("kind", decode.string)
    case tag {
      "ran" -> decode.success(runner.Ran)
      "skip" -> decode.success(runner.RuntimeSkip)
      "error" -> {
        use failure <- decode.then(decode_test_failure())
        decode.success(runner.RunError(failure))
      }
      _ -> decode.success(make_crash_error("Unknown result kind"))
    }
  }

  case decode.run(raw, decoder) {
    Ok(result) -> result
    Error(_) -> make_crash_error("Failed to decode test result")
  }
}

pub fn wrap_pool_result(
  item: Test,
  result: TestRunResult,
  duration_ms: Int,
) -> PoolResult {
  runner.PoolResult(item:, result:, duration_ms:)
}

pub fn make_crash_error(message: String) -> TestRunResult {
  runner.RunError(test_failure.TestFailure(
    message:,
    file: "",
    module: "",
    function: "",
    line: 0,
    kind: test_failure.Generic,
  ))
}

fn decode_test_failure() -> decode.Decoder(TestFailure) {
  use message <- decode.optional_field("message", "", decode.string)
  use file <- decode.optional_field("file", "", decode.string)
  use module <- decode.optional_field("module", "", decode.string)
  use function <- decode.optional_field("fn", "", decode.string)
  use line <- decode.optional_field("line", 0, decode.int)
  use kind <- decode.optional_field(
    "panicKind",
    test_failure.Generic,
    decode_panic_kind_inner(),
  )
  decode.success(test_failure.TestFailure(
    message:,
    file:,
    module:,
    function:,
    line:,
    kind:,
  ))
}

fn decode_panic_kind_inner() -> decode.Decoder(PanicKind) {
  use tag <- decode.field("type", decode.string)
  case tag {
    "assert" -> {
      use start <- decode.optional_field("start", 0, decode.int)
      use end <- decode.optional_field("end", 0, decode.int)
      use expression_start <- decode.optional_field(
        "expressionStart",
        0,
        decode.int,
      )
      use kind <- decode.optional_field(
        "assertKind",
        test_failure.OtherExpression(test_failure.AssertedExpr(
          start: 0,
          end: 0,
          kind: test_failure.Unevaluated,
        )),
        decode_assert_kind_inner(),
      )
      decode.success(test_failure.Assert(start:, end:, expression_start:, kind:))
    }
    "panic" -> decode.success(test_failure.Panic)
    "todo" -> decode.success(test_failure.Todo)
    "let_assert" -> {
      use start <- decode.optional_field("start", 0, decode.int)
      use end <- decode.optional_field("end", 0, decode.int)
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(test_failure.LetAssert(start:, end:, value:))
    }
    _ -> decode.success(test_failure.Generic)
  }
}

fn decode_assert_kind_inner() -> decode.Decoder(AssertKind) {
  let default_expr = test_failure.AssertedExpr(0, 0, test_failure.Unevaluated)

  use tag <- decode.field("type", decode.string)
  case tag {
    "binary_operator" -> {
      use operator <- decode.optional_field("operator", "==", decode.string)
      use left <- decode.optional_field(
        "left",
        default_expr,
        decode_asserted_expr_value(),
      )
      use right <- decode.optional_field(
        "right",
        default_expr,
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
        default_expr,
        decode_asserted_expr_value(),
      )
      decode.success(test_failure.OtherExpression(expr))
    }
    _ -> decode.success(test_failure.OtherExpression(default_expr))
  }
}

fn decode_asserted_expr_value() -> decode.Decoder(AssertedExpr) {
  use start <- decode.optional_field("start", 0, decode.int)
  use end <- decode.optional_field("end", 0, decode.int)
  use kind <- decode.then(decode_expr_kind())
  decode.success(test_failure.AssertedExpr(start:, end:, kind:))
}

fn decode_expr_kind() -> decode.Decoder(ExprKind) {
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
