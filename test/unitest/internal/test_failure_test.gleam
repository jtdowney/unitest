import gleam/option.{None, Some}
import gleam/string
import simplifile
import unitest/internal/test_failure.{
  Assert, AssertedExpr, BinaryOperator, Expression, FunctionCall, Generic,
  LetAssert, Literal, OtherExpression, Panic, TestFailure, Todo,
}

pub fn format_failure_includes_test_name_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )

  let result =
    test_failure.format_failure(
      1,
      "my_module",
      "my_test",
      5,
      failure,
      None,
      False,
    )

  assert string.contains(result, "my_module.my_test")
}

pub fn format_failure_includes_duration_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )

  let result =
    test_failure.format_failure(1, "mod", "test", 42, failure, None, False)

  assert string.contains(result, "42 ms")
}

pub fn format_failure_includes_location_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "test/foo_test.gleam",
      module: "",
      function: "",
      line: 25,
      kind: Generic,
    )

  let result =
    test_failure.format_failure(1, "mod", "test", 0, failure, None, False)

  assert string.contains(result, "test/foo_test.gleam:25")
}

pub fn format_failure_includes_message_test() {
  let failure =
    TestFailure(
      message: "Assertion failed: expected True",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )

  let result =
    test_failure.format_failure(1, "mod", "test", 0, failure, None, False)

  assert string.contains(result, "Assertion failed: expected True")
}

pub fn format_failure_includes_source_snippet_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )

  let result =
    test_failure.format_failure(
      1,
      "mod",
      "test",
      0,
      failure,
      Some("assert x == 5"),
      False,
    )

  assert string.contains(result, "assert x == 5")
}

pub fn format_failure_with_binary_operator_shows_left_right_test() {
  let failure =
    TestFailure(
      message: "Assertion failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Assert(
        start: 0,
        end: 0,
        expression_start: 0,
        kind: BinaryOperator(
          operator: "==",
          left: AssertedExpr(start: 0, end: 0, kind: Expression("5")),
          right: AssertedExpr(start: 0, end: 0, kind: Literal("6")),
        ),
      ),
    )

  let result =
    test_failure.format_failure(
      1,
      "mod",
      "test",
      0,
      failure,
      Some("assert x == 6"),
      False,
    )

  assert string.contains(result, "left:")
  assert string.contains(result, "right:")
  assert string.contains(result, "5")
  assert string.contains(result, "6")
}

pub fn format_failure_with_let_assert_shows_value_test() {
  let failure =
    TestFailure(
      message: "Pattern match failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: LetAssert(start: 0, end: 0, value: "Error(Nil)"),
    )

  let result =
    test_failure.format_failure(1, "mod", "test", 0, failure, None, False)

  assert string.contains(result, "value: Error(Nil)")
}

pub fn format_failure_with_function_call_shows_args_test() {
  let failure =
    TestFailure(
      message: "Assertion failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Assert(
        start: 0,
        end: 0,
        expression_start: 0,
        kind: FunctionCall(arguments: [
          AssertedExpr(start: 0, end: 0, kind: Expression("\"hello\"")),
          AssertedExpr(start: 0, end: 0, kind: Literal("5")),
        ]),
      ),
    )

  let result =
    test_failure.format_failure(1, "mod", "test", 0, failure, None, False)

  assert string.contains(result, "arg 0:")
  assert string.contains(result, "arg 1:")
}

pub fn format_failure_duration_zero_ms_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)
  assert string.contains(result, "< 1 ms")
}

pub fn format_failure_duration_one_ms_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 1, failure, None, False)
  assert string.contains(result, "1 ms")
}

pub fn format_failure_duration_under_one_second_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result =
    test_failure.format_failure(1, "m", "t", 500, failure, None, False)
  assert string.contains(result, "500 ms")
}

pub fn format_failure_duration_exactly_one_second_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result =
    test_failure.format_failure(1, "m", "t", 1000, failure, None, False)
  assert string.contains(result, "1 s")
}

pub fn format_failure_duration_with_remainder_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result =
    test_failure.format_failure(1, "m", "t", 1500, failure, None, False)
  assert string.contains(result, "1.500 s")
}

pub fn format_failure_omits_location_when_file_empty_test() {
  let failure =
    TestFailure(
      message: "err",
      file: "",
      module: "",
      function: "",
      line: 10,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)
  assert !string.contains(result, ":10")
}

pub fn format_failure_omits_location_when_line_zero_test() {
  let failure =
    TestFailure(
      message: "err",
      file: "test.gleam",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)
  assert !string.contains(result, "test.gleam:0")
}

pub fn format_failure_labels_literal_values_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Assert(
        start: 0,
        end: 0,
        expression_start: 0,
        kind: BinaryOperator(
          operator: "==",
          left: AssertedExpr(start: 0, end: 0, kind: Literal("5")),
          right: AssertedExpr(start: 0, end: 0, kind: Literal("6")),
        ),
      ),
    )

  let result =
    test_failure.format_failure(
      1,
      "m",
      "t",
      0,
      failure,
      Some("assert 5 == 6"),
      False,
    )

  assert string.contains(result, "(literal)")
}

pub fn format_failure_labels_expression_values_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Assert(
        start: 0,
        end: 0,
        expression_start: 0,
        kind: BinaryOperator(
          operator: "==",
          left: AssertedExpr(start: 0, end: 0, kind: Expression("5")),
          right: AssertedExpr(start: 0, end: 0, kind: Literal("6")),
        ),
      ),
    )

  let result =
    test_failure.format_failure(
      1,
      "m",
      "t",
      0,
      failure,
      Some("assert x == 6"),
      False,
    )

  assert string.contains(result, "(expression)")
  assert string.contains(result, "(literal)")
}

pub fn extract_snippet_returns_none_for_invalid_start_test() {
  let result = test_failure.extract_snippet("any_file.gleam", 0, 10)
  assert result == None
}

pub fn extract_snippet_returns_none_for_invalid_range_test() {
  let result = test_failure.extract_snippet("any_file.gleam", 10, 5)
  assert result == None
}

pub fn extract_snippet_returns_none_for_missing_file_test() {
  let result =
    test_failure.extract_snippet("nonexistent_file_12345.gleam", 1, 10)
  assert result == None
}

pub fn extract_snippet_extracts_content_from_file_test() {
  let path = "test_snippet_temp.txt"
  let content = "hello world"
  let assert Ok(_) = simplifile.write(path, content)
  let result = test_failure.extract_snippet(path, 6, 11)
  let _ = simplifile.delete(path)
  assert result == Some("world")
}

pub fn extract_snippet_trims_whitespace_test() {
  let path = "test_snippet_trim.txt"
  let content = "hello   world   "
  let assert Ok(_) = simplifile.write(path, content)
  let result = test_failure.extract_snippet(path, 5, 16)
  let _ = simplifile.delete(path)
  assert result == Some("world")
}

pub fn format_failure_with_color_includes_ansi_codes_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, True)

  assert string.contains(result, "\u{001b}[")
}

pub fn format_failure_without_color_has_no_ansi_codes_test() {
  let failure =
    TestFailure(
      message: "failed",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Generic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)

  assert !string.contains(result, "\u{001b}[")
}

pub fn format_failure_with_panic_shows_message_test() {
  let failure =
    TestFailure(
      message: "explicit panic",
      file: "test.gleam",
      module: "",
      function: "",
      line: 5,
      kind: Panic,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)

  assert string.contains(result, "explicit panic")
}

pub fn format_failure_with_todo_shows_message_test() {
  let failure =
    TestFailure(
      message: "not implemented yet",
      file: "test.gleam",
      module: "",
      function: "",
      line: 10,
      kind: Todo,
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)

  assert string.contains(result, "not implemented yet")
}

pub fn format_failure_with_other_expression_shows_value_test() {
  let failure =
    TestFailure(
      message: "",
      file: "",
      module: "",
      function: "",
      line: 0,
      kind: Assert(
        start: 0,
        end: 0,
        expression_start: 0,
        kind: OtherExpression(expression: AssertedExpr(
          start: 0,
          end: 0,
          kind: Expression("False"),
        )),
      ),
    )
  let result = test_failure.format_failure(1, "m", "t", 0, failure, None, False)

  assert string.contains(result, "value: False")
}
