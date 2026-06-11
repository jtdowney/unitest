import birdie
import gleam/list
import gleam/option
import gleam/time/duration
import unitest
import unitest/internal/discovery
import unitest/internal/test_failure.{type TestFailure}

pub fn main() -> Nil {
  unitest.main()
}

fn default_opts() -> unitest.CliOptions {
  unitest.CliOptions(
    seed: option.None,
    filter: unitest.Filter(location: unitest.AllLocations, tag: option.None),
    no_color: False,
    reporter: option.None,
    sort_order: option.None,
    sort_reversed: False,
    workers: option.None,
    timeout: option.None,
  )
}

fn make_result(
  item: discovery.Test,
  outcome: unitest.Outcome,
  duration_ms: Int,
) -> unitest.TestResult {
  unitest.TestResult(
    item:,
    outcome:,
    duration: duration.milliseconds(duration_ms),
  )
}

fn noop_callback(
  _result: unitest.TestResult,
  _progress: unitest.Progress,
  continue: fn() -> Nil,
) -> Nil {
  continue()
}

fn generic_failure(message: String) -> TestFailure {
  test_failure.TestFailure(
    message:,
    file: "",
    line: 0,
    kind: test_failure.Generic,
  )
}

@external(erlang, "unitest_test_ffi", "send_pool_result")
@external(javascript, "./unitest_test_ffi.mjs", "sendPoolResult")
fn send_pool_result(pr: unitest.TestResult) -> Nil

@external(erlang, "unitest_test_ffi", "receive_pool_result_test")
@external(javascript, "./unitest_test_ffi.mjs", "receivePoolResultTest")
fn receive_pool_result_test(callback: fn(unitest.TestResult) -> Nil) -> Nil

fn make_test(
  module: String,
  name: String,
  tags: List(String),
) -> discovery.Test {
  make_test_at(
    module:,
    name:,
    tags:,
    path: "test/" <> module <> ".gleam",
    start_line: 1,
    end_line: 100,
  )
}

fn make_test_at(
  module module: String,
  name name: String,
  tags tags: List(String),
  path path: String,
  start_line start_line: Int,
  end_line end_line: Int,
) -> discovery.Test {
  discovery.Test(
    module:,
    name:,
    tags:,
    file_path: path,
    line_span: discovery.LineSpan(start_line, end_line),
  )
}

fn make_cli_opts(
  location: unitest.LocationFilter,
  tag: option.Option(String),
) -> unitest.CliOptions {
  unitest.CliOptions(..default_opts(), filter: unitest.Filter(location:, tag:))
}

@external(erlang, "unitest_test_ffi", "execute_sync_sequential")
@external(javascript, "./unitest_test_ffi.mjs", "executeSyncSequentialJs")
fn execute_sync_sequential(
  plan: List(unitest.PlanItem),
  seed: Int,
  platform: unitest.Platform,
  on_result: fn(unitest.TestResult, unitest.Progress, fn() -> Nil) -> Nil,
  callback: fn(unitest.ExecuteResult) -> a,
) -> a

@external(erlang, "unitest_test_ffi", "execute_sync_pooled")
@external(javascript, "./unitest_test_ffi.mjs", "executeSyncPooledJs")
fn execute_sync_pooled(
  plan: List(unitest.PlanItem),
  seed: Int,
  workers: Int,
  platform: unitest.Platform,
  on_result: fn(unitest.TestResult, unitest.Progress, fn() -> Nil) -> Nil,
  callback: fn(unitest.ExecuteResult) -> a,
) -> a

fn make_sequential_platform(
  run_test: fn(discovery.Test) -> unitest.Outcome,
  now_ms: fn() -> Int,
) -> unitest.Platform {
  unitest.Platform(
    now_ms:,
    run_test: fn(t, k) { k(run_test(t)) },
    start_module_pool: fn(_groups, _workers) { Nil },
    receive_pool_result: fn(_k) { Nil },
  )
}

fn make_pooled_platform(
  start_module_pool: fn(List(List(discovery.Test)), Int) -> Nil,
) -> unitest.Platform {
  unitest.Platform(
    now_ms: fn() { 100 },
    run_test: fn(_t, _k) { Nil },
    start_module_pool:,
    receive_pool_result: receive_pool_result_test,
  )
}

fn all_passing_pool_platform() -> unitest.Platform {
  make_pooled_platform(fn(groups, _workers) {
    list.each(groups, fn(group) {
      list.each(group, fn(t) {
        send_pool_result(unitest.TestResult(
          t,
          unitest.Passed,
          duration.milliseconds(5),
        ))
      })
    })
  })
}

pub fn exit_code_one_when_failures_test() {
  let report =
    unitest.Report(
      passed: 4,
      failed: 1,
      skipped: 0,
      failures: [],
      seed: 1,
      runtime: duration.milliseconds(100),
    )
  assert unitest.exit_code(report) == 1
}

pub fn exit_code_zero_when_no_failures_test() {
  let report =
    unitest.Report(
      passed: 5,
      failed: 0,
      skipped: 1,
      failures: [],
      seed: 1,
      runtime: duration.milliseconds(100),
    )
  assert unitest.exit_code(report) == 0
}

pub fn parse_package_name_empty_content_returns_error_test() {
  assert unitest.parse_package_name("") == Error(Nil)
}

pub fn parse_package_name_extracts_name_test() {
  let content = "name = \"unitest\"\nversion = \"1.0.0\""
  assert unitest.parse_package_name(content) == Ok("unitest")
}

pub fn parse_package_name_finds_first_name_line_test() {
  let content = "description = \"test\"\nname = \"found\"\nother = \"stuff\""
  assert unitest.parse_package_name(content) == Ok("found")
}

pub fn parse_package_name_ignores_key_with_name_prefix_test() {
  let content = "named_dep = \">= 1.0.0\"\nname = \"realpkg\""
  assert unitest.parse_package_name(content) == Ok("realpkg")
}

pub fn parse_package_name_malformed_line_returns_error_test() {
  let content = "name = noquotes"
  assert unitest.parse_package_name(content) == Error(Nil)
}

pub fn parse_package_name_missing_name_returns_error_test() {
  let content = "version = \"1.0.0\"\ndescription = \"no name here\""
  assert unitest.parse_package_name(content) == Error(Nil)
}

pub fn parse_package_name_with_leading_whitespace_test() {
  let content = "  name = \"mypackage\"\n"
  assert unitest.parse_package_name(content) == Ok("mypackage")
}

pub fn resolve_cli_action_keeps_help_non_fatal_test() {
  let assert Error(help_text) = unitest.parse_cli_args(["--help"])
  assert unitest.resolve_cli_action(["--help"])
    == unitest.ShowCliMessage(message: help_text, exit_code: 0)
}

pub fn resolve_cli_action_keeps_short_help_non_fatal_test() {
  let assert Error(help_text) = unitest.parse_cli_args(["-h"])
  assert unitest.resolve_cli_action(["-h"])
    == unitest.ShowCliMessage(message: help_text, exit_code: 0)
}

pub fn resolve_cli_action_marks_validation_errors_fatal_test() {
  assert unitest.resolve_cli_action(["--workers", "0"])
    == unitest.ShowCliMessage(message: "Workers must be positive", exit_code: 1)
}

pub fn resolve_cli_action_runs_valid_args_test() {
  assert unitest.resolve_cli_action(["--workers", "4"])
    == unitest.RunWithCliOptions(
      unitest.CliOptions(..default_opts(), workers: option.Some(4)),
    )
}

pub fn resolve_execution_mode_auto_above_threshold_resolves_to_parallel_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunParallelAuto,
      runtime_default: 12,
      runnable_count: 100,
    )
    == unitest.ResolvedParallel(12)
}

pub fn resolve_execution_mode_auto_below_threshold_downgrades_to_sequential_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunParallelAuto,
      runtime_default: 12,
      runnable_count: 10,
    )
    == unitest.ResolvedSequential
}

pub fn resolve_execution_mode_cli_workers_override_ignores_threshold_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.Some(4),
      option_mode: unitest.RunParallelAuto,
      runtime_default: 16,
      runnable_count: 10,
    )
    == unitest.ResolvedParallel(4)
}

pub fn resolve_execution_mode_cli_workers_override_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.Some(8),
      option_mode: unitest.RunSequential,
      runtime_default: 16,
      runnable_count: 100,
    )
    == unitest.ResolvedParallel(8)
}

pub fn resolve_execution_mode_explicit_parallel_ignores_threshold_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunParallel(4),
      runtime_default: 16,
      runnable_count: 10,
    )
    == unitest.ResolvedParallel(4)
}

pub fn resolve_execution_mode_parallel_passthrough_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunParallel(4),
      runtime_default: 16,
      runnable_count: 100,
    )
    == unitest.ResolvedParallel(4)
}

pub fn resolve_execution_mode_sequential_passthrough_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunSequential,
      runtime_default: 16,
      runnable_count: 100,
    )
    == unitest.ResolvedSequential
}

pub fn resolve_execution_mode_uses_option_mode_test() {
  assert unitest.resolve_execution_mode(
      cli_workers: option.None,
      option_mode: unitest.RunAsync,
      runtime_default: 16,
      runnable_count: 100,
    )
    == unitest.ResolvedAsync
}

pub fn resolve_package_name_returns_name_for_valid_content_test() {
  assert unitest.resolve_package_name(Ok(
      "name = \"unitest\"\nversion = \"1.0.0\"",
    ))
    == Ok("unitest")
}

pub fn resolve_package_name_returns_parse_error_test() {
  assert unitest.resolve_package_name(Ok("version = \"1.0.0\""))
    == Error("Error: Could not find 'name' in gleam.toml")
}

pub fn resolve_package_name_returns_read_error_test() {
  assert unitest.resolve_package_name(Error(Nil))
    == Error("Error: Could not read gleam.toml")
}

pub fn file_and_tag_combined_test() {
  let result = unitest.parse_cli_args(["test/foo.gleam", "--tag", "slow"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFile("test/foo.gleam"),
      tag: option.Some("slow"),
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn file_with_seed_test() {
  let result = unitest.parse_cli_args(["test/foo.gleam", "--seed", "42"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFile("test/foo.gleam"),
      tag: option.None,
    )
  assert result
    == Ok(unitest.CliOptions(..default_opts(), seed: option.Some(42), filter:))
}

pub fn parse_accepts_timeout_test() {
  let assert Ok(opts) = unitest.parse_cli_args(["--timeout", "5000"])
  assert opts.timeout == option.Some(5000)
}

pub fn parse_accepts_zero_timeout_test() {
  let assert Ok(opts) = unitest.parse_cli_args(["--timeout", "0"])
  assert opts.timeout == option.Some(0)
}

pub fn parse_defaults_timeout_to_none_test() {
  let assert Ok(opts) = unitest.parse_cli_args([])
  assert opts.timeout == option.None
}

pub fn parse_empty_args_test() {
  let result = unitest.parse_cli_args([])
  assert result == Ok(default_opts())
}

pub fn parse_file_backslash_relative_path_test() {
  let result = unitest.parse_cli_args(["test\\foo_test.gleam:10"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFileAtLine(path: "test/foo_test.gleam", line: 10),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_invalid_line_test() {
  let result = unitest.parse_cli_args(["foo_test.gleam:abc"])
  assert result == Error("Invalid line number in file filter: 'abc'")
}

pub fn parse_file_negative_line_test() {
  let result = unitest.parse_cli_args(["foo_test.gleam:-5"])
  assert result == Error("Line number must be positive in file filter: '-5'")
}

pub fn parse_file_positional_arg_test() {
  let result = unitest.parse_cli_args(["test/foo_test.gleam"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFile("test/foo_test.gleam"),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_relative_path_test() {
  let result = unitest.parse_cli_args(["foo_test.gleam:10"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFileAtLine(path: "foo_test.gleam", line: 10),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_windows_absolute_path_test() {
  let result = unitest.parse_cli_args(["C:\\proj\\test\\foo_test.gleam"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFile("C:/proj/test/foo_test.gleam"),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_windows_absolute_path_with_line_test() {
  let result = unitest.parse_cli_args(["C:\\proj\\test\\foo_test.gleam:42"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFileAtLine(
        path: "C:/proj/test/foo_test.gleam",
        line: 42,
      ),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_with_line_positional_test() {
  let result = unitest.parse_cli_args(["test/foo_test.gleam:42"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyFileAtLine(path: "test/foo_test.gleam", line: 42),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_zero_line_test() {
  let result = unitest.parse_cli_args(["foo_test.gleam:0"])
  assert result == Error("Line number must be positive in file filter: '0'")
}

pub fn parse_no_color_flag_test() {
  let result = unitest.parse_cli_args(["--no-color"])
  assert result == Ok(unitest.CliOptions(..default_opts(), no_color: True))
}

pub fn parse_rejects_invalid_reporter_test() {
  assert unitest.parse_cli_args(["--reporter", "json"])
    == Error("Invalid reporter: 'json'. Use 'dot' or 'table'")
}

pub fn parse_rejects_invalid_sort_order_test() {
  assert unitest.parse_cli_args(["--sort", "size"])
    == Error("Invalid sort order: 'size'. Use 'native', 'time', or 'name'")
}

pub fn parse_rejects_invalid_test_filters_test() {
  let invalid_inputs = ["foo_test", "some/module", "foo.", ".bar_test", "."]
  list.each(invalid_inputs, fn(input) {
    assert unitest.parse_cli_args(["--test", input])
      == Error(
        "Invalid --test format: '"
        <> input
        <> "'. Expected: module/path.function_name",
      )
  })
}

pub fn parse_rejects_negative_timeout_test() {
  assert unitest.parse_cli_args(["--timeout", "-1"])
    == Error("Timeout must be zero or positive")
}

pub fn parse_rejects_non_positive_workers_test() {
  let invalid_inputs = ["0", "-1"]
  list.each(invalid_inputs, fn(input) {
    assert unitest.parse_cli_args(["--workers", input])
      == Error("Workers must be positive")
  })
}

pub fn parse_reporter_table_test() {
  let result = unitest.parse_cli_args(["--reporter", "table"])
  assert result
    == Ok(
      unitest.CliOptions(
        ..default_opts(),
        reporter: option.Some(unitest.TableReporter),
      ),
    )
}

pub fn parse_seed_test() {
  let result = unitest.parse_cli_args(["--seed", "123"])
  assert result
    == Ok(unitest.CliOptions(..default_opts(), seed: option.Some(123)))
}

pub fn parse_sort_name_test() {
  let result = unitest.parse_cli_args(["--sort", "name"])
  assert result
    == Ok(
      unitest.CliOptions(
        ..default_opts(),
        sort_order: option.Some(unitest.NameSort),
      ),
    )
}

pub fn parse_sort_time_test() {
  let result = unitest.parse_cli_args(["--sort", "time"])
  assert result
    == Ok(
      unitest.CliOptions(
        ..default_opts(),
        sort_order: option.Some(unitest.TimeSort),
      ),
    )
}

pub fn parse_tag_filter_test() {
  let result = unitest.parse_cli_args(["--tag", "slow"])
  let filter =
    unitest.Filter(location: unitest.AllLocations, tag: option.Some("slow"))
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_test_filter_test() {
  let result = unitest.parse_cli_args(["--test", "foo/bar_test.some_test"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyTest(module: "foo/bar_test", name: "some_test"),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn parse_workers_test() {
  let result = unitest.parse_cli_args(["--workers", "4"])
  assert result
    == Ok(unitest.CliOptions(..default_opts(), workers: option.Some(4)))
}

pub fn seed_combined_with_filter_test() {
  let result = unitest.parse_cli_args(["--seed", "42", "--tag", "slow"])
  let filter =
    unitest.Filter(location: unitest.AllLocations, tag: option.Some("slow"))
  assert result
    == Ok(unitest.CliOptions(..default_opts(), seed: option.Some(42), filter:))
}

pub fn test_takes_precedence_over_positional_file_test() {
  let result = unitest.parse_cli_args(["baz.gleam", "--test", "foo.bar_test"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyTest(module: "foo", name: "bar_test"),
      tag: option.None,
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn test_takes_precedence_over_tag_test() {
  let result =
    unitest.parse_cli_args(["--test", "foo.bar_test", "--tag", "slow"])
  let filter =
    unitest.Filter(
      location: unitest.OnlyTest(module: "foo", name: "bar_test"),
      tag: option.Some("slow"),
    )
  assert result == Ok(unitest.CliOptions(..default_opts(), filter:))
}

pub fn all_failing_tests_table_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])
  let t3 = make_test("bar", "c_test", [])

  let results = [
    make_result(t1, unitest.Failed(generic_failure("assertion failed")), 10),
    make_result(t2, unitest.Failed(generic_failure("expected true")), 25),
    make_result(t3, unitest.Failed(generic_failure("timeout")), 100),
  ]

  unitest.render_table(results, False, unitest.NativeSort, False)
  |> birdie.snap("all failing tests table")
}

pub fn all_passing_tests_table_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])
  let t3 = make_test("bar", "c_test", [])

  let results = [
    make_result(t1, unitest.Passed, 5),
    make_result(t2, unitest.Passed, 12),
    make_result(t3, unitest.Passed, 3),
  ]

  unitest.render_table(results, False, unitest.NativeSort, False)
  |> birdie.snap("all passing tests table")
}

pub fn empty_results_test() {
  let results: List(unitest.TestResult) = []

  unitest.render_table(results, False, unitest.NativeSort, False)
  |> birdie.snap("empty results table")
}

pub fn native_sort_reversed_test() {
  let t1 = make_test("first", "test_a", [])
  let t2 = make_test("second", "test_b", [])
  let t3 = make_test("third", "test_c", [])

  let results = [
    make_result(t1, unitest.Passed, 10),
    make_result(t2, unitest.Passed, 20),
    make_result(t3, unitest.Passed, 30),
  ]

  unitest.render_table(results, False, unitest.NativeSort, True)
  |> birdie.snap(
    "native sort reversed shows results in reverse execution order",
  )
}

pub fn no_color_mode_test() {
  let t1 = make_test("alpha", "first_test", [])
  let t2 = make_test("alpha", "second_test", [])
  let t3 = make_test("beta", "third_test", [])

  let results = [
    make_result(t1, unitest.Passed, 7),
    make_result(t2, unitest.Failed(generic_failure("error")), 20),
    make_result(t3, unitest.Skipped, 0),
  ]

  unitest.render_table(results, False, unitest.NativeSort, False)
  |> birdie.snap("no color mode shows PASS/FAIL/SKIP text")
}

pub fn sort_by_name_ascending_test() {
  let t1 = make_test("zebra", "z_test", [])
  let t2 = make_test("alpha", "b_test", [])
  let t3 = make_test("alpha", "a_test", [])

  let results = [
    make_result(t1, unitest.Passed, 10),
    make_result(t2, unitest.Passed, 20),
    make_result(t3, unitest.Passed, 30),
  ]

  unitest.render_table(results, False, unitest.NameSort, False)
  |> birdie.snap("sort by name shows alphabetical order")
}

pub fn sort_by_name_descending_test() {
  let t1 = make_test("zebra", "z_test", [])
  let t2 = make_test("alpha", "b_test", [])
  let t3 = make_test("alpha", "a_test", [])

  let results = [
    make_result(t1, unitest.Passed, 10),
    make_result(t2, unitest.Passed, 20),
    make_result(t3, unitest.Passed, 30),
  ]

  unitest.render_table(results, False, unitest.NameSort, True)
  |> birdie.snap("sort by name reversed shows reverse alphabetical order")
}

pub fn sort_by_time_ascending_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", [])
  let t3 = make_test("bar", "medium_test", [])

  let results = [
    make_result(t1, unitest.Passed, 5),
    make_result(t2, unitest.Passed, 100),
    make_result(t3, unitest.Passed, 25),
  ]

  unitest.render_table(results, False, unitest.TimeSort, True)
  |> birdie.snap("sort by time reversed shows fastest first")
}

pub fn sort_by_time_descending_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", [])
  let t3 = make_test("bar", "medium_test", [])

  let results = [
    make_result(t1, unitest.Passed, 5),
    make_result(t2, unitest.Passed, 100),
    make_result(t3, unitest.Passed, 25),
  ]

  unitest.render_table(results, False, unitest.TimeSort, False)
  |> birdie.snap("sort by time descending shows slowest first")
}

pub fn sort_by_time_skipped_after_zero_ms_ascending_test() {
  let t1 = make_test("foo", "zero_ms_test", [])
  let t2 = make_test("foo", "skipped_test", [])
  let t3 = make_test("bar", "slow_test", [])
  let t4 = make_test("bar", "medium_test", [])

  let results = [
    make_result(t1, unitest.Passed, 0),
    make_result(t2, unitest.Skipped, 0),
    make_result(t3, unitest.Passed, 100),
    make_result(t4, unitest.Passed, 25),
  ]

  unitest.render_table(results, False, unitest.TimeSort, True)
  |> birdie.snap("sort by time ascending puts skipped after 0ms tests")
}

pub fn sort_by_time_skipped_after_zero_ms_descending_test() {
  let t1 = make_test("foo", "zero_ms_test", [])
  let t2 = make_test("foo", "skipped_test", [])
  let t3 = make_test("bar", "slow_test", [])
  let t4 = make_test("bar", "medium_test", [])

  let results = [
    make_result(t1, unitest.Passed, 0),
    make_result(t2, unitest.Skipped, 0),
    make_result(t3, unitest.Passed, 100),
    make_result(t4, unitest.Passed, 25),
  ]

  unitest.render_table(results, False, unitest.TimeSort, False)
  |> birdie.snap("sort by time descending puts skipped after 0ms tests")
}

pub fn with_color_mode_test() {
  let t1 = make_test("foo", "pass_test", [])
  let t2 = make_test("foo", "fail_test", [])
  let t3 = make_test("bar", "skip_test", [])

  let results = [
    make_result(t1, unitest.Passed, 5),
    make_result(t2, unitest.Failed(generic_failure("failed")), 10),
    make_result(t3, unitest.Skipped, 0),
  ]

  unitest.render_table(results, True, unitest.NativeSort, False)
  |> birdie.snap("color mode shows symbols with ANSI codes")
}

pub fn execute_backfills_missing_failure_location_test() {
  let t1 = make_test("foo", "bad_test", [])
  let plan = [unitest.Run(t1)]

  let platform =
    make_sequential_platform(
      fn(_t) { unitest.Failed(generic_failure("boom")) },
      fn() { 100 },
    )

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let assert [failure] = exec_result.report.failures
  assert failure.error.file == "test/foo.gleam"
  assert failure.error.line == 1
}

pub fn execute_failing_test_counts_failure_test() {
  let t1 = make_test("foo", "bad_test", [])
  let plan = [unitest.Run(t1)]

  let now_ms = fn() { 100 }
  let platform =
    make_sequential_platform(
      fn(_t) { unitest.Failed(generic_failure("assertion failed")) },
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

pub fn execute_keeps_payload_failure_location_test() {
  let t1 = make_test("foo", "bad_test", [])
  let plan = [unitest.Run(t1)]

  let located_failure =
    test_failure.TestFailure(
      message: "boom",
      file: "test/exact.gleam",
      line: 42,
      kind: test_failure.Generic,
    )
  let platform =
    make_sequential_platform(fn(_t) { unitest.Failed(located_failure) }, fn() {
      100
    })

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let assert [failure] = exec_result.report.failures
  assert failure.error.file == "test/exact.gleam"
  assert failure.error.line == 42
}

pub fn execute_passing_tests_counts_passed_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])
  let t3 = make_test("foo", "c_test", [])
  let plan = [unitest.Run(t1), unitest.Run(t2), unitest.Run(t3)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { unitest.Passed }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 42, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 3
  assert report.failed == 0
  assert report.skipped == 0
  assert report.seed == 42
}

pub fn execute_pooled_emits_skip_callbacks_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", ["slow"])
  let t3 = make_test("m", "c_test", [])
  let plan = [unitest.Run(t1), unitest.Skip(t2), unitest.Run(t3)]

  let callback_outcomes = fn(
    result: unitest.TestResult,
    _progress: unitest.Progress,
    continue: fn() -> Nil,
  ) -> Nil {
    case result.outcome {
      unitest.Skipped -> {
        assert result.item.name == "b_test"
      }
      _ -> Nil
    }
    continue()
  }

  use exec_result <- execute_sync_pooled(
    plan,
    1,
    1,
    all_passing_pool_platform(),
    callback_outcomes,
  )

  let outcomes = list.map(exec_result.results, fn(r) { r.outcome })
  assert list.contains(outcomes, unitest.Skipped)
  assert exec_result.report.skipped == 1
}

pub fn execute_pooled_failed_test_in_pool_test() {
  let t1 = make_test("m", "bad_test", [])
  let plan = [unitest.Run(t1)]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(unitest.TestResult(
        t1,
        unitest.Failed(generic_failure("crash bang")),
        duration.milliseconds(12),
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
  let plan = [
    unitest.Run(t1),
    unitest.Run(t2),
    unitest.Skip(t3),
    unitest.Run(t4),
  ]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(unitest.TestResult(
        t1,
        unitest.Passed,
        duration.milliseconds(5),
      ))
      send_pool_result(unitest.TestResult(
        t2,
        unitest.Failed(generic_failure("assertion failed")),
        duration.milliseconds(10),
      ))
      send_pool_result(unitest.TestResult(
        t4,
        unitest.Skipped,
        duration.milliseconds(2),
      ))
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

pub fn execute_pooled_mixed_run_skip_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", ["slow"])
  let t3 = make_test("m", "c_test", [])
  let plan = [unitest.Run(t1), unitest.Skip(t2), unitest.Run(t3)]

  use exec_result <- execute_sync_pooled(
    plan,
    1,
    1,
    all_passing_pool_platform(),
    noop_callback,
  )
  let report = exec_result.report

  assert report.passed == 2
  assert report.failed == 0
  assert report.skipped == 1

  let names = list.map(exec_result.results, fn(r) { r.item.name })
  assert list.contains(names, "a_test")
  assert list.contains(names, "b_test")
  assert list.contains(names, "c_test")
}

pub fn execute_pooled_returns_results_in_completion_order_test() {
  let t1 = make_test("m", "a_test", [])
  let t2 = make_test("m", "b_test", [])
  let t3 = make_test("m", "c_test", [])
  let plan = [unitest.Run(t1), unitest.Run(t2), unitest.Run(t3)]

  let platform =
    make_pooled_platform(fn(_groups, _workers) {
      send_pool_result(unitest.TestResult(
        t2,
        unitest.Passed,
        duration.milliseconds(3),
      ))
      send_pool_result(unitest.TestResult(
        t1,
        unitest.Passed,
        duration.milliseconds(7),
      ))
      send_pool_result(unitest.TestResult(
        t3,
        unitest.Passed,
        duration.milliseconds(1),
      ))
    })

  use exec_result <- execute_sync_pooled(plan, 99, 2, platform, noop_callback)
  assert list.map(exec_result.results, fn(r) { r.item.name })
    == ["b_test", "a_test", "c_test"]
}

pub fn execute_runtime_skip_counts_skipped_test() {
  let t1 = make_test("foo", "guarded_test", [])
  let plan = [unitest.Run(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { unitest.Skipped }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn execute_runtime_uses_injected_clock_test() {
  let t1 = make_test("foo", "a_test", [])
  let plan = [unitest.Run(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { unitest.Passed }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.runtime == duration.milliseconds(0)
}

pub fn execute_skipped_test_counts_skipped_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])
  let plan = [unitest.Skip(t1)]

  let now_ms = fn() { 100 }
  let platform = make_sequential_platform(fn(_t) { unitest.Passed }, now_ms)

  use exec_result <- execute_sync_sequential(plan, 1, platform, noop_callback)
  let report = exec_result.report

  assert report.passed == 0
  assert report.failed == 0
  assert report.skipped == 1
}

pub fn file_and_tag_combined_by_name_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])
  let t2 = make_test("foo", "fast_test", [])
  let t3 = make_test("bar", "slow_test", ["slow"])

  let result =
    unitest.plan(
      [t1, t2, t3],
      make_cli_opts(unitest.OnlyFile("foo.gleam"), option.Some("slow")),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn file_and_tag_combined_includes_matching_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "slow_test",
      tags: ["slow"],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )
  let t2 =
    make_test_at(
      module: "foo",
      name: "fast_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 25,
      end_line: 35,
    )

  let result =
    unitest.plan(
      [t1, t2],
      make_cli_opts(unitest.OnlyFile("test/foo.gleam"), option.Some("slow")),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn file_and_tag_excludes_wrong_file_test() {
  let t1 =
    make_test_at(
      module: "bar",
      name: "slow_test",
      tags: ["slow"],
      path: "test/bar.gleam",
      start_line: 10,
      end_line: 20,
    )

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(unitest.OnlyFile("test/foo.gleam"), option.Some("slow")),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_and_tag_excludes_wrong_tag_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "fast_test",
      tags: ["fast"],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(unitest.OnlyFile("test/foo.gleam"), option.Some("slow")),
      [],
    )

  assert list.is_empty(result)
}

pub fn file_at_line_filter_matches_span_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "first_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )
  let t2 =
    make_test_at(
      module: "foo",
      name: "second_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 25,
      end_line: 35,
    )

  let result =
    unitest.plan(
      [t1, t2],
      make_cli_opts(
        unitest.OnlyFileAtLine(path: "test/foo.gleam", line: 15),
        option.None,
      ),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn file_at_line_no_match_returns_empty_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "a_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(
        unitest.OnlyFileAtLine(path: "test/foo.gleam", line: 50),
        option.None,
      ),
      [],
    )

  assert list.is_empty(result)
}

pub fn ignored_tags_cause_skip_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    unitest.plan([t1, t2], make_cli_opts(unitest.AllLocations, option.None), [
      "slow",
    ])

  assert result == [unitest.Run(t1), unitest.Skip(t2)]
}

pub fn only_file_absolute_path_filter_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "a_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 1,
      end_line: 5,
    )

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(
        unitest.OnlyFile("/home/user/proj/test/foo.gleam"),
        option.None,
      ),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn only_file_filter_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "a_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )
  let t2 =
    make_test_at(
      module: "bar",
      name: "b_test",
      tags: [],
      path: "test/bar.gleam",
      start_line: 5,
      end_line: 15,
    )

  let result =
    unitest.plan(
      [t1, t2],
      make_cli_opts(unitest.OnlyFile("test/foo.gleam"), option.None),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn only_file_relative_path_filter_test() {
  let t1 =
    make_test_at(
      module: "foo",
      name: "a_test",
      tags: [],
      path: "test/foo.gleam",
      start_line: 10,
      end_line: 20,
    )

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(unitest.OnlyFile("foo.gleam"), option.None),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn only_tag_filter_test() {
  let t1 = make_test("foo", "fast_test", [])
  let t2 = make_test("foo", "slow_test", ["slow"])

  let result =
    unitest.plan(
      [t1, t2],
      make_cli_opts(unitest.AllLocations, option.Some("slow")),
      [],
    )

  assert result == [unitest.Run(t2)]
}

pub fn only_test_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result =
    unitest.plan(
      [t1, t2],
      make_cli_opts(unitest.OnlyTest("foo", "a_test"), option.None),
      [],
    )

  assert result == [unitest.Run(t1)]
}

pub fn no_match_message_describes_tag_filter_test() {
  let filter =
    unitest.Filter(location: unitest.AllLocations, tag: option.Some("slow"))
  assert unitest.no_match_message(filter) == "No tests matched tag slow"
}

pub fn no_match_message_describes_file_filter_test() {
  let filter =
    unitest.Filter(
      location: unitest.OnlyFile("test/foo_test.gleam"),
      tag: option.None,
    )
  assert unitest.no_match_message(filter)
    == "No tests matched file test/foo_test.gleam"
}

pub fn no_match_message_describes_test_filter_test() {
  let filter =
    unitest.Filter(
      location: unitest.OnlyTest(module: "foo/bar_test", name: "a_test"),
      tag: option.None,
    )
  assert unitest.no_match_message(filter)
    == "No tests matched test foo/bar_test.a_test"
}

pub fn no_match_message_combines_file_and_tag_test() {
  let filter =
    unitest.Filter(
      location: unitest.OnlyFileAtLine(path: "test/foo_test.gleam", line: 42),
      tag: option.Some("slow"),
    )
  assert unitest.no_match_message(filter)
    == "No tests matched file test/foo_test.gleam:42 and tag slow"
}

pub fn outcome_char_maps_variants_test() {
  assert unitest.outcome_char(unitest.Passed, False) == "."
  assert unitest.outcome_char(unitest.Failed(generic_failure("error")), False)
    == "F"
  assert unitest.outcome_char(unitest.Skipped, False) == "S"
}

pub fn plan_all_with_no_filter_test() {
  let t1 = make_test("foo", "a_test", [])
  let t2 = make_test("foo", "b_test", [])

  let result =
    unitest.plan([t1, t2], make_cli_opts(unitest.AllLocations, option.None), [])

  assert result == [unitest.Run(t1), unitest.Run(t2)]
}

pub fn render_summary_multiple_failures_with_skipped_test() {
  let first_failure =
    unitest.FailureRecord(
      item: make_test("foo", "bad_test", []),
      error: test_failure.TestFailure(
        message: "boom",
        file: "test/foo.gleam",
        line: 12,
        kind: test_failure.Generic,
      ),
      duration: duration.milliseconds(5),
    )
  let second_failure =
    unitest.FailureRecord(
      item: make_test("bar", "worse_test", []),
      error: test_failure.TestFailure(
        message: "",
        file: "test/bar.gleam",
        line: 30,
        kind: test_failure.Timeout(timeout_ms: 1000),
      ),
      duration: duration.milliseconds(1000),
    )
  let report =
    unitest.Report(
      passed: 3,
      failed: 2,
      skipped: 2,
      failures: [first_failure, second_failure],
      seed: 99,
      runtime: duration.milliseconds(250),
    )
  unitest.render_summary(report, False)
  |> birdie.snap("render_summary with multiple failures and skipped")
}

pub fn render_summary_no_failures_test() {
  let report =
    unitest.Report(
      passed: 5,
      failed: 0,
      skipped: 0,
      failures: [],
      seed: 12_345,
      runtime: duration.milliseconds(100),
    )
  unitest.render_summary(report, False)
  |> birdie.snap("render_summary with no failures")
}

pub fn render_summary_one_failure_test() {
  let failure =
    unitest.FailureRecord(
      item: make_test("foo", "bad_test", []),
      error: test_failure.TestFailure(
        message: "boom",
        file: "test/foo.gleam",
        line: 12,
        kind: test_failure.Generic,
      ),
      duration: duration.milliseconds(5),
    )
  let report =
    unitest.Report(
      passed: 2,
      failed: 1,
      skipped: 0,
      failures: [failure],
      seed: 42,
      runtime: duration.milliseconds(100),
    )
  unitest.render_summary(report, False)
  |> birdie.snap("render_summary with one failure")
}

pub fn tag_filter_overrides_ignored_tags_test() {
  let t1 = make_test("foo", "slow_test", ["slow"])

  let result =
    unitest.plan(
      [t1],
      make_cli_opts(unitest.AllLocations, option.Some("slow")),
      [
        "slow",
      ],
    )

  assert result == [unitest.Run(t1)]
}
