import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import unitest/internal/discover.{type Test}
import unitest/internal/runner.{
  type PoolResult, type TestRunResult, PoolResult, Ran, RunError, RuntimeSkip,
}
import unitest/internal/test_failure.{
  type AssertKind, type AssertedExpr, type ExprKind, type PanicKind,
  type TestFailure, Assert, AssertedExpr, BinaryOperator, Expression,
  FunctionCall, Generic, LetAssert, Literal, OtherExpression, Panic, TestFailure,
  Todo, Unevaluated,
}

pub fn decode_test_run_result(raw: Dynamic) -> TestRunResult {
  let decoder = {
    use tag <- decode.field("kind", decode.string)
    case tag {
      "ran" -> decode.success(Ran)
      "skip" -> decode.success(RuntimeSkip)
      "error" -> {
        use failure <- decode.then(decode_test_failure())
        decode.success(RunError(failure))
      }
      _ ->
        decode.success(
          RunError(TestFailure("Unknown result kind", "", "", "", 0, Generic)),
        )
    }
  }

  case decode.run(raw, decoder) {
    Ok(result) -> result
    Error(_) ->
      RunError(TestFailure(
        "Failed to decode test result",
        "",
        "",
        "",
        0,
        Generic,
      ))
  }
}

pub fn wrap_pool_result(
  item: Test,
  result: TestRunResult,
  duration_ms: Int,
) -> PoolResult {
  PoolResult(item:, result:, duration_ms:)
}

pub fn make_crash_error(message: String) -> TestRunResult {
  RunError(TestFailure(message, "", "", "", 0, Generic))
}

fn decode_test_failure() -> decode.Decoder(TestFailure) {
  use message <- decode.optional_field("message", "", decode.string)
  use file <- decode.optional_field("file", "", decode.string)
  use module <- decode.optional_field("module", "", decode.string)
  use function <- decode.optional_field("fn", "", decode.string)
  use line <- decode.optional_field("line", 0, decode.int)
  use kind <- decode.optional_field(
    "panicKind",
    Generic,
    decode_panic_kind_inner(),
  )
  decode.success(TestFailure(message, file, module, function, line, kind))
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
        OtherExpression(AssertedExpr(0, 0, Unevaluated)),
        decode_assert_kind_inner(),
      )
      decode.success(Assert(start:, end:, expression_start:, kind:))
    }
    "panic" -> decode.success(Panic)
    "todo" -> decode.success(Todo)
    "let_assert" -> {
      use start <- decode.optional_field("start", 0, decode.int)
      use end <- decode.optional_field("end", 0, decode.int)
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(LetAssert(start:, end:, value:))
    }
    _ -> decode.success(Generic)
  }
}

fn decode_assert_kind_inner() -> decode.Decoder(AssertKind) {
  let default_expr = AssertedExpr(0, 0, Unevaluated)

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
      decode.success(BinaryOperator(operator:, left:, right:))
    }
    "function_call" -> {
      use args <- decode.optional_field(
        "arguments",
        [],
        decode.list(decode_asserted_expr_value()),
      )
      decode.success(FunctionCall(args))
    }
    "other_expression" -> {
      use expr <- decode.optional_field(
        "expression",
        default_expr,
        decode_asserted_expr_value(),
      )
      decode.success(OtherExpression(expr))
    }
    _ -> decode.success(OtherExpression(default_expr))
  }
}

fn decode_asserted_expr_value() -> decode.Decoder(AssertedExpr) {
  use start <- decode.optional_field("start", 0, decode.int)
  use end <- decode.optional_field("end", 0, decode.int)
  use kind <- decode.then(decode_expr_kind())
  decode.success(AssertedExpr(start:, end:, kind:))
}

fn decode_expr_kind() -> decode.Decoder(ExprKind) {
  use tag <- decode.optional_field("kind", "", decode.string)
  case tag {
    "literal" -> {
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(Literal(value))
    }
    "expression" -> {
      use value <- decode.optional_field("value", "", decode.string)
      decode.success(Expression(value))
    }
    _ -> decode.success(Unevaluated)
  }
}
