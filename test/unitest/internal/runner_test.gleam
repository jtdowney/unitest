import gleam/list
import gleam/option.{None, Some}
import gleam/string
import unitest/internal/cli
import unitest/internal/discover.{type Test, LineSpan, Test}
import unitest/internal/runner.{
  type ExecuteResult, type Platform, type Progress, type TestResult, Failed,
  Passed, Platform, Ran, Report, Run, RunError, RuntimeSkip, Skip, Skipped,
}
import unitest/internal/test_failure.{type TestFailure, Generic, TestFailure}

fn noop_callback(
  _result: TestResult,
  _progress: Progress,
  continue: fn() -> Nil,
) -> Nil {
  continue()
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

fn make_test(module: String, name: String, tags: List(String)) -> Test {
  Test(
    module: module,
    name: name,
    tags: tags,
    file_path: "test/" <> module <> ".gleam",
    line_span: LineSpan(1, 100),
  )
}

fn make_cli_opts(
  location: cli.LocationFilter,
  tag: option.Option(String),
) -> cli.CliOptions {
  cli.CliOptions(
    seed: None,
    filter: cli.Filter(location:, tag:),
    no_color: False,
    reporter: cli.DotReporter,
    sort_order: None,
    sort_reversed: False,
  )
}

@external(erlang, "unitest_test_ffi", "execute_sync")
@external(javascript, "../../unitest_test_ffi.mjs", "executeSyncJs")
fn execute_sync(
  plan: List(runner.PlanItem),
  seed: Int,
  platform: Platform,
  on_result: fn(TestResult, Progress, fn() -> Nil) -> Nil,
  callback: fn(ExecuteResult) -> a,
) -> a

pub fn execute_passing_tests_counts_passed_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])
  let t3 = make_test("foo", "c_test", [])
  let plan = [Run(t1), Run(t2), Run(t3)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t, k) { k(Ran) },
      print: fn(_s) { Nil },
    )

  use exec_result <- execute_sync(plan, 42, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 3
  assert report.failed == 0
  assert report.skipped == 0
  assert report.seed == 42
}

pub fn execute_failing_test_counts_failure_test() {
  let t1 = make_test("foo", "bad_test", [])
  let plan = [Run(t1)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t, k) { k(RunError(test_failure("assertion failed"))) },
      print: fn(_s) { Nil },
    )

  use exec_result <- execute_sync(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 1
  assert list.length(report.failures) == 1

  let assert [failure] = report.failures
  assert failure.item == t1
  let assert Failed(error) = failure.outcome
  assert error.message == "assertion failed"
}

pub fn execute_skipped_test_counts_skipped_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])
  let plan = [Skip(t1)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t, k) { k(Ran) },
      print: fn(_s) { Nil },
    )

  use exec_result <- execute_sync(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn execute_captures_runtime_test() {
  let t1 = make_test("foo", "a_test", [])
  let plan = [Run(t1)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t, k) { k(Ran) },
      print: fn(_s) { Nil },
    )

  use exec_result <- execute_sync(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.runtime_ms == 0
}

pub fn execute_runtime_skip_counts_skipped_test() {
  let t1 = make_test("foo", "guarded_test", [])
  let plan = [Run(t1)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t, k) { k(RuntimeSkip) },
      print: fn(_s) { Nil },
    )

  use exec_result <- execute_sync(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn plan_all_with_no_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result = runner.plan([t1, t2], make_cli_opts(cli.AllLocations, None), [])

  assert result == [Run(t1), Run(t2)]
}

pub fn ignored_tags_cause_skip_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan([t1, t2], make_cli_opts(cli.AllLocations, None), ["slow"])

  assert result == [Run(t1), Skip(t2)]
}

pub fn only_test_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyTest("foo", "a_test"), None),
      [],
    )

  assert result == [Run(t1)]
}

pub fn only_tag_filter_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan([t1, t2], make_cli_opts(cli.AllLocations, Some("slow")), [])

  assert result == [Run(t2)]
}

pub fn tag_filter_overrides_ignored_tags_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan([t1], make_cli_opts(cli.AllLocations, Some("slow")), ["slow"])

  assert result == [Run(t1)]
}

pub fn passed_maps_to_dot_test() {
  assert runner.outcome_char(Passed, False) == "."
}

pub fn failed_maps_to_f_test() {
  assert runner.outcome_char(Failed(test_failure("error")), False) == "F"
}

pub fn skipped_maps_to_s_test() {
  assert runner.outcome_char(Skipped, False) == "S"
}

pub fn outcome_char_with_color_includes_ansi_test() {
  let passed = runner.outcome_char(Passed, True)
  let failed = runner.outcome_char(Failed(test_failure("e")), True)
  let skipped = runner.outcome_char(Skipped, True)

  assert string.contains(passed, ".") && string.contains(passed, "\u{001b}[")
  assert string.contains(failed, "F") && string.contains(failed, "\u{001b}[")
  assert string.contains(skipped, "S") && string.contains(skipped, "\u{001b}[")
}

pub fn summary_includes_seed_test() {
  let report =
    Report(
      passed: 3,
      failed: 0,
      skipped: 0,
      failures: [],
      seed: 12_345,
      runtime_ms: 100,
    )
  let summary = runner.render_summary(report, False)
  assert string.contains(summary, "Seed: 12345")
}

pub fn summary_includes_totals_test() {
  let report =
    Report(
      passed: 5,
      failed: 0,
      skipped: 0,
      failures: [],
      seed: 1,
      runtime_ms: 50,
    )
  let summary = runner.render_summary(report, False)
  assert string.contains(summary, "5 passed, no failures")
}

pub fn only_file_filter_test() {
  let t1 =
    Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )
  let t2 =
    Test(
      module: "bar",
      name: "b_test",
      tags: [],
      file_path: "test/bar.gleam",
      line_span: LineSpan(5, 15),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), None),
      [],
    )

  assert result == [Run(t1)]
}

pub fn only_file_relative_path_filter_test() {
  let t1 =
    Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )

  let result =
    runner.plan([t1], make_cli_opts(cli.OnlyFile("foo.gleam"), None), [])

  assert result == [Run(t1)]
}

pub fn file_at_line_filter_matches_span_test() {
  let t1 =
    Test(
      module: "foo",
      name: "first_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )
  let t2 =
    Test(
      module: "foo",
      name: "second_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(25, 35),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyFileAtLine(path: "test/foo.gleam", line: 15), None),
      [],
    )

  assert result == [Run(t1)]
}

pub fn file_at_line_no_match_returns_empty_test() {
  let t1 =
    Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(cli.OnlyFileAtLine(path: "test/foo.gleam", line: 50), None),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_combined_includes_matching_test() {
  let t1 =
    Test(
      module: "foo",
      name: "slow_test",
      tags: ["slow"],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )
  let t2 =
    Test(
      module: "foo",
      name: "fast_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: LineSpan(25, 35),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), Some("slow")),
      [],
    )

  assert result == [Run(t1)]
}

pub fn file_and_tag_excludes_wrong_tag_test() {
  let t1 =
    Test(
      module: "foo",
      name: "fast_test",
      tags: ["fast"],
      file_path: "test/foo.gleam",
      line_span: LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), Some("slow")),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_excludes_wrong_file_test() {
  let t1 =
    Test(
      module: "bar",
      name: "slow_test",
      tags: ["slow"],
      file_path: "test/bar.gleam",
      line_span: LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), Some("slow")),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_combined_by_name_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])
  let t2 = make_test("foo", "fast_test", [])
  let t3 = make_test("bar", "slow_test", ["slow"])

  let result =
    runner.plan(
      [t1, t2, t3],
      make_cli_opts(cli.OnlyFile("foo.gleam"), Some("slow")),
      [],
    )

  assert result == [Run(t1)]
}
