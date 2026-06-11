import birdie
import gleam/option
import gleam/time/duration
import simplifile
import temporary
import unitest/internal/test_failure.{type TestFailure}

fn binary_operator_failure(
  message message: String,
  left left: test_failure.ExprKind,
  right right: test_failure.ExprKind,
) -> TestFailure {
  test_failure.TestFailure(
    message:,
    file: "",
    line: 0,
    kind: test_failure.Assert(
      start: 0,
      end: 0,
      kind: test_failure.BinaryOperator(
        operator: "==",
        left: test_failure.AssertedExpr(start: 0, end: 0, kind: left),
        right: test_failure.AssertedExpr(start: 0, end: 0, kind: right),
      ),
    ),
  )
}

fn frame(module: String, file: String) -> test_failure.StackFrame {
  test_failure.StackFrame(module:, function: "f", arity: 0, file:, line: 1)
}

fn generic_failure(message: String) -> TestFailure {
  test_failure.TestFailure(
    message:,
    file: "",
    line: 0,
    kind: test_failure.Generic,
  )
}

fn with_snippet_file(run: fn(String) -> a) -> a {
  let assert Ok(result) = {
    use path <- temporary.create(temporary.file())
    let assert Ok(Nil) =
      simplifile.write(
        path,
        "hello   world
",
      )
    run(path)
  }
  result
}

pub fn drop_internal_frames_keeps_user_drops_unitest_test() {
  let my_mod = frame("my_mod", "src/my_mod.gleam")
  let helpers = frame("my_unitest_helpers", "src/my_unitest_helpers.gleam")
  let utils = frame("unitest_utils", "src/unitest_unitest.gleam")

  let input = [
    my_mod,
    frame("unitest", "src/unitest.gleam"),
    helpers,
    frame("unitest@internal@runner", "src/unitest/internal/unitest.gleam"),
    utils,
    frame("unitest_ffi", "src/unitest_ffi.erl"),
    frame(
      "runner",
      "/app/build/dev/javascript/unitest/unitest@internal@unitest.mjs",
    ),
    frame("task_queues", "node:internal/process/task_queues"),
  ]

  assert test_failure.drop_internal_frames(input) == [my_mod, helpers, utils]
}

pub fn extract_snippet_extracts_content_from_file_test() {
  use path <- with_snippet_file
  assert test_failure.extract_snippet(path, 8, 13) == Ok("world")
}

pub fn extract_snippet_returns_none_for_invalid_range_test() {
  let result = test_failure.extract_snippet("any_file.gleam", 10, 5)
  assert result == Error(Nil)
}

pub fn extract_snippet_returns_none_for_invalid_start_test() {
  let result = test_failure.extract_snippet("any_file.gleam", 0, 10)
  assert result == Error(Nil)
}

pub fn extract_snippet_returns_none_for_missing_file_test() {
  let result =
    test_failure.extract_snippet("nonexistent_file_12345.gleam", 1, 10)
  assert result == Error(Nil)
}

pub fn extract_snippet_trims_whitespace_test() {
  use path <- with_snippet_file
  assert test_failure.extract_snippet(path, 5, 13) == Ok("world")
}

pub fn format_failure_generic_test() {
  let failure = generic_failure("Assertion failed: expected True")
  test_failure.format_failure(
    index: 1,
    module: "my_module",
    name: "my_test",
    duration: duration.milliseconds(42),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure generic with header and message")
}

pub fn format_failure_includes_location_test() {
  let failure =
    test_failure.TestFailure(
      ..generic_failure("failed"),
      file: "test/foo_test.gleam",
      line: 25,
    )
  test_failure.format_failure(
    index: 1,
    module: "mod",
    name: "test",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with location")
}

pub fn format_failure_includes_source_snippet_test() {
  let failure = generic_failure("failed")
  test_failure.format_failure(
    index: 1,
    module: "mod",
    name: "test",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.Some("assert x == 5"),
    use_color: False,
  )
  |> birdie.snap("format_failure with source snippet")
}

pub fn format_failure_labels_expression_values_test() {
  let failure =
    binary_operator_failure(
      message: "",
      left: test_failure.Expression("5"),
      right: test_failure.Literal("6"),
    )

  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.Some("assert x == 6"),
    use_color: False,
  )
  |> birdie.snap("format_failure labels expression and literal values")
}

pub fn format_failure_labels_literal_values_test() {
  let failure =
    binary_operator_failure(
      message: "",
      left: test_failure.Literal("5"),
      right: test_failure.Literal("6"),
    )

  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.Some("assert 5 == 6"),
    use_color: False,
  )
  |> birdie.snap("format_failure labels literal values")
}

pub fn format_failure_omits_location_when_file_empty_test() {
  let failure = test_failure.TestFailure(..generic_failure("err"), line: 10)
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure omits location when file empty")
}

pub fn format_failure_omits_location_when_line_zero_test() {
  let failure =
    test_failure.TestFailure(..generic_failure("err"), file: "test.gleam")
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure omits location when line zero")
}

pub fn format_failure_with_binary_operator_test() {
  let failure =
    binary_operator_failure(
      message: "Assertion failed",
      left: test_failure.Expression("5"),
      right: test_failure.Literal("6"),
    )

  test_failure.format_failure(
    index: 1,
    module: "mod",
    name: "test",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.Some("assert x == 6"),
    use_color: False,
  )
  |> birdie.snap("format_failure with binary operator")
}

pub fn format_failure_with_color_test() {
  let failure = generic_failure("failed")
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: True,
  )
  |> birdie.snap("format_failure with color includes ansi codes")
}

pub fn format_failure_with_crashed_reason_test() {
  let failure =
    test_failure.TestFailure(
      ..generic_failure(""),
      kind: test_failure.Crashed("killed", []),
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with crashed reason")
}

pub fn format_failure_with_crashed_stack_frames_test() {
  let failure =
    test_failure.TestFailure(
      ..generic_failure(""),
      kind: test_failure.Crashed("badmatch", [
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
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with crashed stack frames")
}

pub fn format_failure_with_function_call_test() {
  let failure =
    test_failure.TestFailure(
      message: "Assertion failed",
      file: "",
      line: 0,
      kind: test_failure.Assert(
        start: 0,
        end: 0,
        kind: test_failure.FunctionCall(arguments: [
          test_failure.AssertedExpr(
            start: 0,
            end: 0,
            kind: test_failure.Expression("\"hello\""),
          ),
          test_failure.AssertedExpr(
            start: 0,
            end: 0,
            kind: test_failure.Literal("5"),
          ),
        ]),
      ),
    )

  test_failure.format_failure(
    index: 1,
    module: "mod",
    name: "test",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with function call args")
}

pub fn format_failure_with_let_assert_test() {
  let failure =
    test_failure.TestFailure(
      message: "Pattern match failed",
      file: "",
      line: 0,
      kind: test_failure.LetAssert(start: 0, end: 0, value: "Error(Nil)"),
    )

  test_failure.format_failure(
    index: 1,
    module: "mod",
    name: "test",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with let assert value")
}

pub fn format_failure_with_other_expression_test() {
  let failure =
    test_failure.TestFailure(
      message: "",
      file: "",
      line: 0,
      kind: test_failure.Assert(
        start: 0,
        end: 0,
        kind: test_failure.OtherExpression(
          expression: test_failure.AssertedExpr(
            start: 0,
            end: 0,
            kind: test_failure.Expression("False"),
          ),
        ),
      ),
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with other expression value")
}

pub fn format_failure_with_panic_test() {
  let failure =
    test_failure.TestFailure(
      message: "explicit panic",
      file: "test.gleam",
      line: 5,
      kind: test_failure.Panic,
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with panic")
}

pub fn format_failure_with_timeout_test() {
  let failure =
    test_failure.TestFailure(
      ..generic_failure(""),
      kind: test_failure.Timeout(5000),
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with timeout")
}

pub fn format_failure_with_todo_test() {
  let failure =
    test_failure.TestFailure(
      message: "not implemented yet",
      file: "test.gleam",
      line: 10,
      kind: test_failure.Todo,
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with todo")
}

pub fn format_failure_with_undef_test() {
  let failure =
    test_failure.TestFailure(
      ..generic_failure(""),
      kind: test_failure.Undef(module: "my_mod", function: "missing", arity: 2),
    )
  test_failure.format_failure(
    index: 1,
    module: "m",
    name: "t",
    duration: duration.milliseconds(0),
    error: failure,
    source: option.None,
    use_color: False,
  )
  |> birdie.snap("format_failure with undef")
}
