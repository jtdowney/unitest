import gleam/list
import gleam/option.{None}
import gleam/string
import unitest/internal/cli
import unitest/internal/discover.{Test}
import unitest/internal/runner.{
  Failed, Passed, Platform, Report, Run, Skip, Skipped,
}

// --- Execution tests (from run_test.gleam) ---

pub fn execute_passing_tests_counts_passed_test() {
  let t1 = Test(module: "foo", name: "a_test", tags: [])
  let t2 = Test(module: "foo", name: "b_test", tags: [])
  let t3 = Test(module: "foo", name: "c_test", tags: [])
  let plan = [Run(t1), Run(t2), Run(t3)]

  let platform =
    Platform(now_ms: fn() { 100 }, run_test: fn(_t) { Ok(Nil) }, print: fn(_s) {
      Nil
    })

  let report = runner.execute(plan, 42, platform, False)

  assert report.passed == 3
  assert report.failed == 0
  assert report.skipped == 0
  assert report.seed == 42
}

pub fn execute_failing_test_counts_failure_test() {
  let t1 = Test(module: "foo", name: "bad_test", tags: [])
  let plan = [Run(t1)]

  let platform =
    Platform(
      now_ms: fn() { 100 },
      run_test: fn(_t) { Error("assertion failed") },
      print: fn(_s) { Nil },
    )

  let report = runner.execute(plan, 1, platform, False)

  assert report.passed == 0
  assert report.failed == 1
  assert list.length(report.failures) == 1

  let assert [failure] = report.failures
  assert failure.item == t1
  assert failure.reason == "assertion failed"
}

pub fn execute_skipped_test_counts_skipped_test() {
  let t1 = Test(module: "foo", name: "slow_test", tags: ["slow"])
  let plan = [Skip(t1)]

  let platform =
    Platform(now_ms: fn() { 100 }, run_test: fn(_t) { Ok(Nil) }, print: fn(_s) {
      Nil
    })

  let report = runner.execute(plan, 1, platform, False)

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn execute_captures_runtime_test() {
  let t1 = Test(module: "foo", name: "a_test", tags: [])
  let plan = [Run(t1)]

  let platform =
    Platform(now_ms: fn() { 100 }, run_test: fn(_t) { Ok(Nil) }, print: fn(_s) {
      Nil
    })

  let report = runner.execute(plan, 1, platform, False)

  // With constant time, runtime = end - start = 100 - 100 = 0
  assert report.runtime_ms == 0
}

// --- Planning tests (from select_test.gleam) ---

pub fn plan_all_with_no_filter_test() {
  let t1 = Test(module: "foo", name: "a_test", tags: [])
  let t2 = Test(module: "foo", name: "b_test", tags: [])
  let cli_opts = cli.CliOptions(seed: None, filter: cli.All, no_color: False)

  let result = runner.plan([t1, t2], cli_opts, [])

  assert result == [Run(t1), Run(t2)]
}

pub fn ignored_tags_cause_skip_test() {
  let t1 = Test(module: "foo", name: "fast_test", tags: [])
  let t2 = Test(module: "foo", name: "slow_test", tags: ["slow"])
  let cli_opts = cli.CliOptions(seed: None, filter: cli.All, no_color: False)

  let result = runner.plan([t1, t2], cli_opts, ["slow"])

  assert result == [Run(t1), Skip(t2)]
}

pub fn only_module_filter_test() {
  let t1 = Test(module: "foo", name: "a_test", tags: [])
  let t2 = Test(module: "bar", name: "b_test", tags: [])
  let cli_opts =
    cli.CliOptions(seed: None, filter: cli.OnlyModule("foo"), no_color: False)

  let result = runner.plan([t1, t2], cli_opts, [])

  assert result == [Run(t1)]
}

pub fn only_test_filter_test() {
  let t1 = Test(module: "foo", name: "a_test", tags: [])
  let t2 = Test(module: "foo", name: "b_test", tags: [])
  let cli_opts =
    cli.CliOptions(
      seed: None,
      filter: cli.OnlyTest("foo", "a_test"),
      no_color: False,
    )

  let result = runner.plan([t1, t2], cli_opts, [])

  assert result == [Run(t1)]
}

pub fn only_tag_filter_test() {
  let t1 = Test(module: "foo", name: "fast_test", tags: [])
  let t2 = Test(module: "foo", name: "slow_test", tags: ["slow"])
  let cli_opts =
    cli.CliOptions(seed: None, filter: cli.OnlyTag("slow"), no_color: False)

  let result = runner.plan([t1, t2], cli_opts, [])

  assert result == [Run(t2)]
}

pub fn tag_filter_overrides_ignored_tags_test() {
  let t1 = Test(module: "foo", name: "slow_test", tags: ["slow"])
  let cli_opts =
    cli.CliOptions(seed: None, filter: cli.OnlyTag("slow"), no_color: False)

  let result = runner.plan([t1], cli_opts, ["slow"])

  // Even though "slow" is in ignored_tags, using --tag slow should run it
  assert result == [Run(t1)]
}

// --- Shuffle tests (from rng_test.gleam) ---

pub fn shuffle_is_deterministic_test() {
  let items = [1, 2, 3, 4, 5]
  let result = runner.shuffle(items, 1)
  assert result == [2, 4, 5, 1, 3]
}

pub fn same_seed_produces_same_order_test() {
  let items = [1, 2, 3, 4, 5]
  let first = runner.shuffle(items, 42)
  let second = runner.shuffle(items, 42)
  assert first == second
}

pub fn different_seed_produces_different_order_test() {
  let items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let first = runner.shuffle(items, 1)
  let second = runner.shuffle(items, 2)
  assert first != second
}

pub fn empty_list_returns_empty_test() {
  let items: List(Int) = []
  let result = runner.shuffle(items, 1)
  assert result == []
}

pub fn single_item_returns_same_test() {
  let items = [42]
  let result = runner.shuffle(items, 1)
  assert result == [42]
}

// --- Formatting tests (from format_dot_test.gleam) ---

pub fn passed_maps_to_dot_test() {
  assert runner.outcome_char(Passed, False) == "."
}

pub fn failed_maps_to_f_test() {
  assert runner.outcome_char(Failed("error"), False) == "F"
}

pub fn skipped_maps_to_s_test() {
  assert runner.outcome_char(Skipped, False) == "S"
}

pub fn passed_maps_to_green_dot_when_colored_test() {
  let result = runner.outcome_char(Passed, True)
  assert string.contains(result, ".")
  assert string.contains(result, "\u{001b}[")
}

pub fn failed_maps_to_red_f_when_colored_test() {
  let result = runner.outcome_char(Failed("error"), True)
  assert string.contains(result, "F")
  assert string.contains(result, "\u{001b}[")
}

pub fn skipped_maps_to_yellow_s_when_colored_test() {
  let result = runner.outcome_char(Skipped, True)
  assert string.contains(result, "S")
  assert string.contains(result, "\u{001b}[")
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
