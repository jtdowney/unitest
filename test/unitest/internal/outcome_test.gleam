import gleam/dynamic.{type Dynamic}
import unitest
import unitest/internal/outcome
import unitest/internal/test_failure

fn prop(key: String, value: Dynamic) -> #(Dynamic, Dynamic) {
  #(dynamic.string(key), value)
}

fn make_error_result(
  message message: String,
  file file: String,
  line line: Int,
  failure_kind failure_kind: Dynamic,
) -> Dynamic {
  dynamic.properties([
    prop("kind", dynamic.string("error")),
    prop("message", dynamic.string(message)),
    prop("file", dynamic.string(file)),
    prop("line", dynamic.int(line)),
    prop("failureKind", failure_kind),
  ])
}

fn make_assert_kind(start: Int, end: Int, assert_kind: Dynamic) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("assert")),
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("assertKind", assert_kind),
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

fn make_error_result_no_failure_kind(message: String) -> Dynamic {
  dynamic.properties([
    prop("kind", dynamic.string("error")),
    prop("message", dynamic.string(message)),
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

fn make_asserted_expr_no_value(start: Int, end: Int, kind: String) -> Dynamic {
  dynamic.properties([
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("kind", dynamic.string(kind)),
  ])
}

fn make_other_expr_kind(expression: Dynamic) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("other_expression")),
    prop("expression", expression),
  ])
}

fn make_crashed_kind(reason: String) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("crashed")),
    prop("reason", dynamic.string(reason)),
  ])
}

fn make_stack_frame(
  module: String,
  function: String,
  arity: Int,
  file: String,
  line: Int,
) -> Dynamic {
  dynamic.properties([
    prop("module", dynamic.string(module)),
    prop("function", dynamic.string(function)),
    prop("arity", dynamic.int(arity)),
    prop("file", dynamic.string(file)),
    prop("line", dynamic.int(line)),
  ])
}

fn make_crashed_kind_with_stack(
  reason: String,
  stack: List(Dynamic),
) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("crashed")),
    prop("reason", dynamic.string(reason)),
    prop("stack", dynamic.list(stack)),
  ])
}

fn make_generic_kind() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("generic"))])
}

fn make_let_assert_kind(start: Int, end: Int, value: String) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("let_assert")),
    prop("start", dynamic.int(start)),
    prop("end", dynamic.int(end)),
    prop("value", dynamic.string(value)),
  ])
}

fn make_panic_kind() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("panic"))])
}

fn make_timeout_kind(timeout_ms: Int) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("timeout")),
    prop("timeout_ms", dynamic.int(timeout_ms)),
  ])
}

fn make_todo_kind() -> Dynamic {
  dynamic.properties([prop("type", dynamic.string("todo"))])
}

fn make_undef_kind(module: String, function: String, arity: Int) -> Dynamic {
  dynamic.properties([
    prop("type", dynamic.string("undef")),
    prop("module", dynamic.string(module)),
    prop("function", dynamic.string(function)),
    prop("arity", dynamic.int(arity)),
  ])
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

pub fn decode_error_missing_failure_kind_defaults_to_generic_test() {
  let raw = make_error_result_no_failure_kind("oops")
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "oops",
      file: "",
      line: 0,
      kind: test_failure.Generic,
    ))
}

pub fn decode_error_with_assert_binary_operator_test() {
  let left = make_asserted_expr(10, 20, "literal", "1")
  let right = make_asserted_expr(25, 35, "expression", "x")
  let assert_kind = make_binary_op_kind("==", left, right)
  let raw =
    make_error_result(
      message: "assert failed",
      file: "src/d.gleam",
      line: 30,
      failure_kind: make_assert_kind(5, 40, assert_kind),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "assert failed",
      file: "src/d.gleam",
      line: 30,
      kind: test_failure.Assert(
        start: 5,
        end: 40,
        kind: test_failure.BinaryOperator(
          operator: "==",
          left: test_failure.AssertedExpr(10, 20, test_failure.Literal("1")),
          right: test_failure.AssertedExpr(25, 35, test_failure.Expression("x")),
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
      message: "fn call assert",
      file: "src/e.gleam",
      line: 50,
      failure_kind: make_assert_kind(0, 60, assert_kind),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "fn call assert",
      file: "src/e.gleam",
      line: 50,
      kind: test_failure.Assert(
        start: 0,
        end: 60,
        kind: test_failure.FunctionCall([
          test_failure.AssertedExpr(1, 5, test_failure.Literal("hello")),
          test_failure.AssertedExpr(7, 12, test_failure.Unevaluated),
        ]),
      ),
    ))
}

pub fn decode_error_with_assert_other_expression_test() {
  let expr = make_asserted_expr(3, 8, "expression", "foo()")
  let assert_kind = make_other_expr_kind(expr)
  let raw =
    make_error_result(
      message: "other expr",
      file: "src/f.gleam",
      line: 70,
      failure_kind: make_assert_kind(1, 80, assert_kind),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "other expr",
      file: "src/f.gleam",
      line: 70,
      kind: test_failure.Assert(
        start: 1,
        end: 80,
        kind: test_failure.OtherExpression(test_failure.AssertedExpr(
          3,
          8,
          test_failure.Expression("foo()"),
        )),
      ),
    ))
}

pub fn decode_error_with_crashed_kind_no_frame_test() {
  let raw = make_error_result("", "", 0, make_crashed_kind("badmatch"))
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "",
      file: "",
      line: 0,
      kind: test_failure.Crashed(reason: "badmatch", stack: []),
    ))
}

pub fn decode_error_with_crashed_kind_stack_test() {
  let stack = [
    make_stack_frame("my_mod", "run", 1, "src/my_mod.gleam", 12),
    make_stack_frame("my_mod", "call", 0, "src/my_mod.gleam", 5),
  ]
  let raw =
    make_error_result(
      "",
      "",
      0,
      make_crashed_kind_with_stack("badmatch", stack),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "",
      file: "",
      line: 0,
      kind: test_failure.Crashed(reason: "badmatch", stack: [
        test_failure.StackFrame(
          module: "my_mod",
          function: "run",
          arity: 1,
          file: "src/my_mod.gleam",
          line: 12,
        ),
        test_failure.StackFrame(
          module: "my_mod",
          function: "call",
          arity: 0,
          file: "src/my_mod.gleam",
          line: 5,
        ),
      ]),
    ))
}

pub fn decode_error_with_generic_test() {
  let raw =
    make_error_result(
      "something broke",
      "src/foo.gleam",
      42,
      make_generic_kind(),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "something broke",
      file: "src/foo.gleam",
      line: 42,
      kind: test_failure.Generic,
    ))
}

pub fn decode_error_with_let_assert_kind_test() {
  let raw =
    make_error_result(
      message: "let assert failed",
      file: "src/c.gleam",
      line: 20,
      failure_kind: make_let_assert_kind(100, 200, "Error(Nil)"),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "let assert failed",
      file: "src/c.gleam",
      line: 20,
      kind: test_failure.LetAssert(start: 100, end: 200, value: "Error(Nil)"),
    ))
}

pub fn decode_error_with_panic_test() {
  let raw =
    make_error_result(
      message: "panicked",
      file: "src/a.gleam",
      line: 10,
      failure_kind: make_panic_kind(),
    )
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "panicked",
      file: "src/a.gleam",
      line: 10,
      kind: test_failure.Panic,
    ))
}

pub fn decode_error_with_timeout_kind_test() {
  let raw = make_error_result("", "", 0, make_timeout_kind(5000))
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "",
      file: "",
      line: 0,
      kind: test_failure.Timeout(timeout_ms: 5000),
    ))
}

pub fn decode_error_with_todo_kind_test() {
  let raw = make_error_result("not done", "src/b.gleam", 5, make_todo_kind())
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "not done",
      file: "src/b.gleam",
      line: 5,
      kind: test_failure.Todo,
    ))
}

pub fn decode_error_with_undef_kind_test() {
  let raw =
    make_error_result("", "", 0, make_undef_kind("my/mod", "my_test", 0))
  let result = outcome.from_dynamic(raw)
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "",
      file: "",
      line: 0,
      kind: test_failure.Undef(module: "my/mod", function: "my_test", arity: 0),
    ))
}

pub fn decode_malformed_input_returns_run_error_test() {
  let result = outcome.from_dynamic(dynamic.int(42))
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "Failed to decode test result",
      file: "",
      line: 0,
      kind: test_failure.Generic,
    ))
}

pub fn decode_ran_result_test() {
  let result = outcome.from_dynamic(make_ran_result())
  assert result == unitest.Passed
}

pub fn decode_skip_result_test() {
  let result = outcome.from_dynamic(make_skip_result())
  assert result == unitest.Skipped
}

pub fn decode_unknown_kind_falls_back_to_error_test() {
  let result = outcome.from_dynamic(make_unknown_result())
  assert result
    == unitest.Failed(test_failure.TestFailure(
      message: "Unknown result kind",
      file: "",
      line: 0,
      kind: test_failure.Generic,
    ))
}
