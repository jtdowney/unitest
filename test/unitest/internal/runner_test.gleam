import gleam/list
import gleam/option
import gleam/string
import unitest/internal/cli
import unitest/internal/discover
import unitest/internal/runner
import unitest/internal/test_failure.{type TestFailure}

fn noop_callback(
  _result: runner.TestResult,
  _progress: runner.Progress,
  continue: fn() -> Nil,
) -> Nil {
  continue()
}

fn test_failure(message: String) -> TestFailure {
  test_failure.TestFailure(
    message: message,
    file: "",
    module: "",
    function: "",
    line: 0,
    kind: test_failure.Generic,
  )
}

@external(erlang, "unitest_test_ffi", "send_pool_result")
@external(javascript, "../../unitest_test_ffi.mjs", "sendPoolResult")
fn send_pool_result(pr: runner.PoolResult) -> Nil

@external(erlang, "unitest_test_ffi", "receive_pool_result_test")
@external(javascript, "../../unitest_test_ffi.mjs", "receivePoolResultTest")
fn receive_pool_result_test(callback: fn(runner.PoolResult) -> Nil) -> Nil

fn make_test(module: String, name: String, tags: List(String)) -> discover.Test {
  discover.Test(
    module: module,
    name: name,
    tags: tags,
    file_path: "test/" <> module <> ".gleam",
    line_span: discover.LineSpan(1, 100),
  )
}

fn make_cli_opts(
  location: cli.LocationFilter,
  tag: option.Option(String),
) -> cli.Options {
  cli.Options(
    seed: option.None,
    filter: cli.Filter(location:, tag:),
    no_color: False,
    reporter: cli.DotReporter,
    sort_order: option.None,
    sort_reversed: False,
    workers: option.None,
  )
}

@external(erlang, "unitest_test_ffi", "execute_sync_sequential")
@external(javascript, "../../unitest_test_ffi.mjs", "executeSyncSequentialJs")
fn execute_sync_sequential(
  plan: List(runner.PlanItem),
  seed: Int,
  platform: runner.Platform,
  on_result: fn(runner.TestResult, runner.Progress, fn() -> Nil) -> Nil,
  callback: fn(runner.ExecuteResult) -> a,
) -> a

@external(erlang, "unitest_test_ffi", "execute_sync_pooled")
@external(javascript, "../../unitest_test_ffi.mjs", "executeSyncPooledJs")
fn execute_sync_pooled(
  plan: List(runner.PlanItem),
  seed: Int,
  workers: Int,
  platform: runner.Platform,
  on_result: fn(runner.TestResult, runner.Progress, fn() -> Nil) -> Nil,
  callback: fn(runner.ExecuteResult) -> a,
) -> a

fn make_sequential_platform(
  run_test: fn(discover.Test) -> runner.TestRunResult,
  now_ms: fn() -> Int,
) -> runner.Platform {
  runner.Platform(
    now_ms:,
    run_test: fn(t, k) { k(run_test(t)) },
    start_module_pool: fn(_groups, _workers) { Nil },
    receive_pool_result: fn(_k) { Nil },
    print: fn(_s) { Nil },
  )
}

fn make_pooled_platform(
  start_module_pool: fn(List(List(discover.Test)), Int) -> Nil,
) -> runner.Platform {
  runner.Platform(
    now_ms: fn() { 100 },
    run_test: fn(_t, _k) { Nil },
    start_module_pool:,
    receive_pool_result: receive_pool_result_test,
    print: fn(_s) { Nil },
  )
}

pub fn execute_passing_tests_counts_passed_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])
  let t3 = make_test("foo", "c_test", [])
  let plan = [runner.Run(t1), runner.Run(t2), runner.Run(t3)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { runner.Ran }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 42, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 3
  assert report.failed == 0
  assert report.skipped == 0
  assert report.seed == 42
}

pub fn execute_failing_test_counts_failure_test() {
  let t1 = make_test("foo", "bad_test", [])
  let plan = [runner.Run(t1)]

  let now_ms = fn() { 100 }
  let platform =
    make_sequential_platform(
      fn(_t) { runner.RunError(test_failure("assertion failed")) },
      now_ms,
    )

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 1
  assert list.length(report.failures) == 1

  let assert [failure] = report.failures
  assert failure.item == t1
  assert failure.error.message == "assertion failed"
}

pub fn execute_skipped_test_counts_skipped_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])
  let plan = [runner.Skip(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { runner.Ran }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn execute_captures_runtime_test() {
  let t1 = make_test("foo", "a_test", [])
  let plan = [runner.Run(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { runner.Ran }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.runtime_ms == 0
}

pub fn execute_runtime_skip_counts_skipped_test() {
  let t1 = make_test("foo", "guarded_test", [])
  let plan = [runner.Run(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { runner.RuntimeSkip }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn plan_all_with_no_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result =
    runner.plan([t1, t2], make_cli_opts(cli.AllLocations, option.None), [])

  assert result == [runner.Run(t1), runner.Run(t2)]
}

pub fn ignored_tags_cause_skip_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan([t1, t2], make_cli_opts(cli.AllLocations, option.None), ["slow"])

  assert result == [runner.Run(t1), runner.Skip(t2)]
}

pub fn only_test_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyTest("foo", "a_test"), option.None),
      [],
    )

  assert result == [runner.Run(t1)]
}

pub fn only_tag_filter_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.AllLocations, option.Some("slow")),
      [],
    )

  assert result == [runner.Run(t2)]
}

pub fn tag_filter_overrides_ignored_tags_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])

  let result =
    runner.plan([t1], make_cli_opts(cli.AllLocations, option.Some("slow")), [
      "slow",
    ])

  assert result == [runner.Run(t1)]
}

pub fn passed_maps_to_dot_test() {
  assert runner.outcome_char(runner.Passed, False) == "."
}

pub fn failed_maps_to_f_test() {
  assert runner.outcome_char(runner.Failed(test_failure("error")), False) == "F"
}

pub fn skipped_maps_to_s_test() {
  assert runner.outcome_char(runner.Skipped, False) == "S"
}

pub fn outcome_char_with_color_includes_ansi_test() {
  let passed = runner.outcome_char(runner.Passed, True)
  let failed = runner.outcome_char(runner.Failed(test_failure("e")), True)
  let skipped = runner.outcome_char(runner.Skipped, True)

  assert string.contains(passed, ".") && string.contains(passed, "\u{001b}[")
  assert string.contains(failed, "F") && string.contains(failed, "\u{001b}[")
  assert string.contains(skipped, "S") && string.contains(skipped, "\u{001b}[")
}

pub fn summary_includes_seed_test() {
  let report =
    runner.Report(
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
    runner.Report(
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
    discover.Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )
  let t2 =
    discover.Test(
      module: "bar",
      name: "b_test",
      tags: [],
      file_path: "test/bar.gleam",
      line_span: discover.LineSpan(5, 15),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), option.None),
      [],
    )

  assert result == [runner.Run(t1)]
}

pub fn only_file_relative_path_filter_test() {
  let t1 =
    discover.Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )

  let result =
    runner.plan([t1], make_cli_opts(cli.OnlyFile("foo.gleam"), option.None), [])

  assert result == [runner.Run(t1)]
}

pub fn file_at_line_filter_matches_span_test() {
  let t1 =
    discover.Test(
      module: "foo",
      name: "first_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )
  let t2 =
    discover.Test(
      module: "foo",
      name: "second_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(25, 35),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(
        cli.OnlyFileAtLine(path: "test/foo.gleam", line: 15),
        option.None,
      ),
      [],
    )

  assert result == [runner.Run(t1)]
}

pub fn file_at_line_no_match_returns_empty_test() {
  let t1 =
    discover.Test(
      module: "foo",
      name: "a_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(
        cli.OnlyFileAtLine(path: "test/foo.gleam", line: 50),
        option.None,
      ),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_combined_includes_matching_test() {
  let t1 =
    discover.Test(
      module: "foo",
      name: "slow_test",
      tags: ["slow"],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )
  let t2 =
    discover.Test(
      module: "foo",
      name: "fast_test",
      tags: [],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(25, 35),
    )

  let result =
    runner.plan(
      [t1, t2],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), option.Some("slow")),
      [],
    )

  assert result == [runner.Run(t1)]
}

pub fn file_and_tag_excludes_wrong_tag_test() {
  let t1 =
    discover.Test(
      module: "foo",
      name: "fast_test",
      tags: ["fast"],
      file_path: "test/foo.gleam",
      line_span: discover.LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), option.Some("slow")),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_excludes_wrong_file_test() {
  let t1 =
    discover.Test(
      module: "bar",
      name: "slow_test",
      tags: ["slow"],
      file_path: "test/bar.gleam",
      line_span: discover.LineSpan(10, 20),
    )

  let result =
    runner.plan(
      [t1],
      make_cli_opts(cli.OnlyFile("test/foo.gleam"), option.Some("slow")),
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
      make_cli_opts(cli.OnlyFile("foo.gleam"), option.Some("slow")),
      [],
    )

  assert result == [runner.Run(t1)]
}

pub fn execute_pooled_returns_results_in_completion_order_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", [])
  let t3 = make_test("m", "c_test", [])
  let plan = [runner.Run(t1), runner.Run(t2), runner.Run(t3)]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(runner.PoolResult(t2, runner.Ran, 3))
      send_pool_result(runner.PoolResult(t1, runner.Ran, 7))
      send_pool_result(runner.PoolResult(t3, runner.Ran, 1))
    })

  use exec_result <- execute_sync_pooled(plan, 99, 2, platform, noop_callback)
  assert list.map(exec_result.results, fn(r) { r.item.name })
    == ["b_test", "a_test", "c_test"]
}

pub fn execute_pooled_mixed_run_skip_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", ["slow"])
  let t3 = make_test("m", "c_test", [])
  let plan = [runner.Run(t1), runner.Skip(t2), runner.Run(t3)]

  let platform =
    make_pooled_platform(fn(groups, _workers) {
      list.each(groups, fn(group) {
        list.each(group, fn(t) {
          send_pool_result(runner.PoolResult(t, runner.Ran, 5))
        })
      })
    })

  use exec_result <- execute_sync_pooled(plan, 1, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 2
  assert report.failed == 0
  assert report.skipped == 1

  let names = list.map(exec_result.results, fn(r) { r.item.name })
  assert list.contains(names, "a_test")
  assert list.contains(names, "b_test")
  assert list.contains(names, "c_test")
}

pub fn execute_pooled_failed_test_in_pool_test() {
  let t1 = make_test("m", "bad_test", [])
  let plan = [runner.Run(t1)]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(runner.PoolResult(
        t1,
        runner.RunError(test_failure("crash bang")),
        12,
      ))
    })

  use exec_result <- execute_sync_pooled(plan, 1, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 1
  assert report.skipped == 0
  assert list.length(report.failures) == 1

  let assert [failure] = report.failures
  assert failure.item == t1
  assert failure.error.message == "crash bang"
}

pub fn execute_pooled_mixed_pass_fail_skip_test() {
  let t1 = make_test("m", "pass_test", [])
  let t2 = make_test("m", "fail_test", [])
  let t3 = make_test("m", "skip_test", ["slow"])
  let t4 = make_test("m", "runtime_skip_test", [])
  let plan = [runner.Run(t1), runner.Run(t2), runner.Skip(t3), runner.Run(t4)]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(runner.PoolResult(t1, runner.Ran, 5))
      send_pool_result(runner.PoolResult(
        t2,
        runner.RunError(test_failure("assertion failed")),
        10,
      ))
      send_pool_result(runner.PoolResult(t4, runner.RuntimeSkip, 2))
    })

  use exec_result <- execute_sync_pooled(plan, 1, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 1
  assert report.failed == 1
  assert report.skipped == 2

  assert list.length(report.failures) == 1
  let assert [failure] = report.failures
  assert failure.item == t2
}

pub fn execute_pooled_emits_skip_callbacks_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", ["slow"])
  let t3 = make_test("m", "c_test", [])
  let plan = [runner.Run(t1), runner.Skip(t2), runner.Run(t3)]

  let callback_outcomes = fn(
    result: runner.TestResult,
    _progress: runner.Progress,
    continue: fn() -> Nil,
  ) -> Nil {
    case result.outcome {
      runner.Skipped -> {
        assert result.item.name == "b_test"
      }
      _ -> Nil
    }
    continue()
  }

  let platform =
    make_pooled_platform(fn(groups, _workers) {
      list.each(groups, fn(group) {
        list.each(group, fn(t) {
          send_pool_result(runner.PoolResult(t, runner.Ran, 5))
        })
      })
    })

  use exec_result <- execute_sync_pooled(
    plan,
    1,
    1,
    platform,
    callback_outcomes,
  )

  let outcomes = list.map(exec_result.results, fn(r) { r.outcome })
  assert list.contains(outcomes, runner.Skipped)
  assert exec_result.report.skipped == 1
}
