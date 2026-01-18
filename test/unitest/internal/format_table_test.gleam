import birdie
import unitest/internal/discover.{type Test, LineSpan, Test}
import unitest/internal/format_table
import unitest/internal/runner.{
  type TestResult, Failed, Passed, Skipped, TestResult,
}
import unitest/internal/test_failure.{type TestFailure, Generic, TestFailure}

fn make_test(module: String, name: String) -> Test {
  Test(
    module: module,
    name: name,
    tags: [],
    file_path: "test/" <> module <> ".gleam",
    line_span: LineSpan(1, 10),
  )
}

fn make_result(
  item: Test,
  outcome: runner.Outcome,
  duration_ms: Int,
) -> TestResult {
  TestResult(item: item, outcome: outcome, duration_ms: duration_ms)
}

fn test_failure(message: String) -> TestFailure {
  TestFailure(
    message: message,
    file: "",
    module: "",
    function: "",
    line: 0,
    kind: Generic,
  )
}

pub fn all_passing_tests_with_color_test() {
  let t1 = make_test("foo", "a_test")
  let t2 = make_test("foo", "b_test")
  let t3 = make_test("bar", "c_test")

  let results = [
    make_result(t1, Passed, 5),
    make_result(t2, Passed, 12),
    make_result(t3, Passed, 3),
  ]

  format_table.render_table(results, False)
  |> birdie.snap("all passing tests table")
}

pub fn all_failing_tests_with_color_test() {
  let t1 = make_test("foo", "a_test")
  let t2 = make_test("foo", "b_test")
  let t3 = make_test("bar", "c_test")

  let results = [
    make_result(t1, Failed(test_failure("assertion failed")), 10),
    make_result(t2, Failed(test_failure("expected true")), 25),
    make_result(t3, Failed(test_failure("timeout")), 100),
  ]

  format_table.render_table(results, False)
  |> birdie.snap("all failing tests table")
}

pub fn mixed_results_with_color_test() {
  let t1 = make_test("foo", "passing_test")
  let t2 = make_test("foo", "failing_test")
  let t3 = make_test("bar", "skipped_test")
  let t4 = make_test("bar", "another_pass_test")

  let results = [
    make_result(t1, Passed, 8),
    make_result(t2, Failed(test_failure("unexpected value")), 15),
    make_result(t3, Skipped, 0),
    make_result(t4, Passed, 4),
  ]

  format_table.render_table(results, False)
  |> birdie.snap("mixed results table")
}

pub fn no_color_mode_test() {
  let t1 = make_test("alpha", "first_test")
  let t2 = make_test("alpha", "second_test")
  let t3 = make_test("beta", "third_test")

  let results = [
    make_result(t1, Passed, 7),
    make_result(t2, Failed(test_failure("error")), 20),
    make_result(t3, Skipped, 0),
  ]

  format_table.render_table(results, False)
  |> birdie.snap("no color mode shows PASS/FAIL/SKIP text")
}

pub fn empty_results_test() {
  let results: List(TestResult) = []

  format_table.render_table(results, False)
  |> birdie.snap("empty results table")
}

pub fn with_color_mode_test() {
  let t1 = make_test("foo", "pass_test")
  let t2 = make_test("foo", "fail_test")
  let t3 = make_test("bar", "skip_test")

  let results = [
    make_result(t1, Passed, 5),
    make_result(t2, Failed(test_failure("failed")), 10),
    make_result(t3, Skipped, 0),
  ]

  format_table.render_table(results, True)
  |> birdie.snap("color mode shows symbols with ANSI codes")
}
