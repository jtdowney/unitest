import gleam/dynamic.{type Dynamic}
import unitest/internal/discover.{LineSpan, Test}
import unitest/internal/js_decode
import unitest/internal/runner.{PoolResult, Ran, RunError, RuntimeSkip}
import unitest/internal/test_failure.{
  Assert, AssertedExpr, BinaryOperator, Expression, FunctionCall, Generic,
  LetAssert, Literal, OtherExpression, Panic, TestFailure, Todo, Unevaluated,
}

fn prop(key: String, value: Dynamic) -> #(Dynamic, Dynamic) {
  #(dynamic.string(key), value)
}

fn make_ran_result() -> Dynamic {
  dynamic.properties([prop("kind", dynamic.string("ran"))])
}

fn make_skip_result() -> Dynamic {
  dynamic.properties([prop("kind", dynamic.string("skip"))])
}

fn make_unknown_result() -> Dynamic {
  dynamic.properties([prop("kind", dynamic.string("wat"))])
}

fn make_error_result(
  message: String,
  file: String,
  module: String,
  fn_name: String,
  line: Int,
  panic_kind: Dynamic,
) -> Dynamic {
  dynamic.properties([
    prop("kind", dynamic.string("error")),
    prop("message", dynamic.string(message)),
    prop("file", dynamic.string(file)),
    prop("module", dynamic.string(module)),
    prop("fn", dynamic.string(fn_name)),
    prop("line", dynamic.int(line)),
    prop("panicKind", panic_kind),
  ])
}

fn make_error_result_no_panic_kind(message: String) -> Dynamic {
  dynamic.properties([
    prop("kind", dynamic.string("error")),
    prop("message", dynamic.string(message)),
  ])
}

fn make_generic_panic() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("generic"))])
}

fn make_panic_panic() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("panic"))])
}

fn make_todo_panic() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("todo"))])
}

fn make_assert_panic(
  start: Int,
  end: Int,
  expression_start: Int,
  assert_kind: Dynamic,
) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("assert")),
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("expressionStart", dynamic.int(expression_start)),
    prop("assertKind", assert_kind),
  ])
}

fn make_let_assert_panic(start: Int, end: Int, value: String) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("let_assert")),
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("value", dynamic.string(value)),
  ])
}

fn make_binary_op_kind(
  operator: String,
  left: Dynamic,
  right: Dynamic,
) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("binary_operator")),
    prop("operator", dynamic.string(operator)),
    prop("left", left),
    prop("right", right),
  ])
}

fn make_fn_call_kind(args: List(Dynamic)) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("function_call")),
    prop("arguments", dynamic.list(args)),
  ])
}

fn make_other_expr_kind(expression: Dynamic) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("other_expression")),
    prop("expression", expression),
  ])
}

fn make_asserted_expr(
  start: Int,
  end: Int,
  kind: String,
  value: String,
) -> Dynamic {
  dynamic.properties([
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("kind", dynamic.string(kind)),
    prop("value", dynamic.string(value)),
  ])
}

fn make_asserted_expr_no_value(start: Int, end: Int, kind: String) -> Dynamic {
  dynamic.properties([
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("kind", dynamic.string(kind)),
  ])
}

pub fn decode_ran_result_test() {
  let result = js_decode.decode_test_run_result(make_ran_result())
  assert result == Ran
}

pub fn decode_skip_result_test() {
  let result = js_decode.decode_test_run_result(make_skip_result())
  assert result == RuntimeSkip
}

pub fn decode_unknown_kind_falls_back_to_error_test() {
  let result = js_decode.decode_test_run_result(make_unknown_result())
  assert result
    == RunError(TestFailure("Unknown result kind", "", "", "", 0, Generic))
}

pub fn decode_error_with_generic_panic_test() {
  let raw =
    make_error_result(
      "something broke",
      "src/foo.gleam",
      "foo",
      "bar",
      42,
      make_generic_panic(),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure(
      "something broke",
      "src/foo.gleam",
      "foo",
      "bar",
      42,
      Generic,
    ))
}

pub fn decode_error_with_panic_kind_test() {
  let raw =
    make_error_result(
      "panicked",
      "src/a.gleam",
      "a",
      "f",
      10,
      make_panic_panic(),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure("panicked", "src/a.gleam", "a", "f", 10, Panic))
}

pub fn decode_error_with_todo_kind_test() {
  let raw =
    make_error_result("not done", "src/b.gleam", "b", "g", 5, make_todo_panic())
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure("not done", "src/b.gleam", "b", "g", 5, Todo))
}

pub fn decode_error_with_let_assert_kind_test() {
  let raw =
    make_error_result(
      "let assert failed",
      "src/c.gleam",
      "c",
      "h",
      20,
      make_let_assert_panic(100, 200, "Error(Nil)"),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure(
      "let assert failed",
      "src/c.gleam",
      "c",
      "h",
      20,
      LetAssert(start: 100, end: 200, value: "Error(Nil)"),
    ))
}

pub fn decode_error_with_assert_binary_operator_test() {
  let left = make_asserted_expr(10, 20, "literal", "1")
  let right = make_asserted_expr(25, 35, "expression", "x")
  let assert_kind = make_binary_op_kind("==", left, right)
  let raw =
    make_error_result(
      "assert failed",
      "src/d.gleam",
      "d",
      "i",
      30,
      make_assert_panic(5, 40, 15, assert_kind),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure(
      "assert failed",
      "src/d.gleam",
      "d",
      "i",
      30,
      Assert(
        start: 5,
        end: 40,
        expression_start: 15,
        kind: BinaryOperator(
          operator: "==",
          left: AssertedExpr(10, 20, Literal("1")),
          right: AssertedExpr(25, 35, Expression("x")),
        ),
      ),
    ))
}

pub fn decode_error_with_assert_function_call_test() {
  let arg0 = make_asserted_expr(1, 5, "literal", "hello")
  let arg1 = make_asserted_expr_no_value(7, 12, "unevaluated")
  let assert_kind = make_fn_call_kind([arg0, arg1])
  let raw =
    make_error_result(
      "fn call assert",
      "src/e.gleam",
      "e",
      "j",
      50,
      make_assert_panic(0, 60, 10, assert_kind),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure(
      "fn call assert",
      "src/e.gleam",
      "e",
      "j",
      50,
      Assert(
        start: 0,
        end: 60,
        expression_start: 10,
        kind: FunctionCall([
          AssertedExpr(1, 5, Literal("hello")),
          AssertedExpr(7, 12, Unevaluated),
        ]),
      ),
    ))
}

pub fn decode_error_with_assert_other_expression_test() {
  let expr = make_asserted_expr(3, 8, "expression", "foo()")
  let assert_kind = make_other_expr_kind(expr)
  let raw =
    make_error_result(
      "other expr",
      "src/f.gleam",
      "f",
      "k",
      70,
      make_assert_panic(1, 80, 5, assert_kind),
    )
  let result = js_decode.decode_test_run_result(raw)
  assert result
    == RunError(TestFailure(
      "other expr",
      "src/f.gleam",
      "f",
      "k",
      70,
      Assert(
        start: 1,
        end: 80,
        expression_start: 5,
        kind: OtherExpression(AssertedExpr(3, 8, Expression("foo()"))),
      ),
    ))
}

pub fn decode_error_missing_panic_kind_defaults_to_generic_test() {
  let raw = make_error_result_no_panic_kind("oops")
  let result = js_decode.decode_test_run_result(raw)
  assert result == RunError(TestFailure("oops", "", "", "", 0, Generic))
}

pub fn wrap_pool_result_test() {
  let item =
    Test(
      module: "my_mod",
      name: "my_test",
      tags: [],
      file_path: "test/my_mod.gleam",
      line_span: LineSpan(1, 10),
    )
  let result = js_decode.wrap_pool_result(item, Ran, 42)
  assert result == PoolResult(item:, result: Ran, duration_ms: 42)
}

pub fn decode_malformed_input_returns_run_error_test() {
  let result = js_decode.decode_test_run_result(dynamic.int(42))
  assert result
    == RunError(TestFailure(
      "Failed to decode test result",
      "",
      "",
      "",
      0,
      Generic,
    ))
}

pub fn make_crash_error_test() {
  let result = js_decode.make_crash_error("Worker crashed: timeout")
  assert result
    == RunError(TestFailure("Worker crashed: timeout", "", "", "", 0, Generic))
}
