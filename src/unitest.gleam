//// Unitest is a drop-in replacement for gleeunit that adds random test
//// ordering (with reproducible seeds), tagging, and CLI filtering.

import argv
import clip
import clip/arg
import clip/flag
import clip/help
import clip/opt
import envoy
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/string
import gleam/time/duration
import gleam_community/ansi
import prng/random
import simplifile
import spinner
import tobble
import unitest/internal/discovery
import unitest/internal/test_failure.{type TestFailure}
import unitest/internal/utils

/// Controls how tests are executed.
pub type ExecutionMode {
  /// Runs one test at a time.
  RunSequential
  /// Runs tests concurrently within each module.
  RunAsync
  /// Runs tests in parallel with the given number of workers. On Erlang,
  /// each worker takes a module group and runs its tests concurrently up to
  /// the CPU core count. On JavaScript, each worker is a worker thread that
  /// runs one test at a time, pulling tests from a shared queue.
  RunParallel(workers: Int)
  /// Auto-detects the number of parallel workers. Falls back to sequential
  /// when the test count is below the parallel threshold.
  RunParallelAuto
}

/// How the table reporter orders test results.
pub type SortOrder {
  /// The order tests ran in.
  NativeSort
  /// By duration, slowest first.
  TimeSort
  /// Alphabetical by module, then test name.
  NameSort
}

/// Configuration for the test run.
pub opaque type Options {
  Options(
    seed: Option(Int),
    ignored_tags: List(String),
    reporter: Reporter,
    sort_order: SortOrder,
    sort_reversed: Bool,
    check_results: Bool,
    execution_mode: ExecutionMode,
    timeout: duration.Duration,
  )
}

/// Treat `Error(reason)` returns as failures.
pub fn check_results(options: Options, check_results: Bool) -> Options {
  Options(..options, check_results:)
}

/// Returns default options:
///
/// - no fixed seed (random ordering each run)
/// - no ignored tags
/// - sequential execution
/// - 60 second per-test timeout
/// - dot reporter
/// - table sort order: native (run) order, not reversed
/// - `Error(_)` returns not treated as failures
pub fn defaults() -> Options {
  Options(
    seed: option.None,
    ignored_tags: [],
    reporter: DotReporter,
    sort_order: NativeSort,
    sort_reversed: False,
    check_results: False,
    execution_mode: RunSequential,
    timeout: duration.seconds(60),
  )
}

/// Set how tests are executed (sequential, async, or parallel).
pub fn execution_mode(options: Options, mode: ExecutionMode) -> Options {
  Options(..options, execution_mode: mode)
}

/// Conditionally skip a test at runtime based on a boolean condition.
///
/// Use with Gleam's `use` syntax. If the condition is `False`, the test
/// is skipped and reported as `S` in the output.
///
/// ## Example
///
/// ```gleam
/// pub fn otp28_feature_test() {
///   use <- unitest.guard(otp_version() >= 28)
///   // test runs only if OTP >= 28
/// }
/// ```
///
/// Multiple guards can be chained:
///
/// ```gleam
/// pub fn linux_otp28_test() {
///   use <- unitest.guard(is_linux())
///   use <- unitest.guard(otp_version() >= 28)
///   // runs only if both conditions are true
/// }
/// ```
pub fn guard(when condition: Bool, otherwise next: fn() -> a) -> a {
  bool.lazy_guard(when: !condition, return: skip, otherwise: next)
}

/// Set the tags to skip (reported as `S`).
pub fn ignored_tags(options: Options, tags: List(String)) -> Options {
  Options(..options, ignored_tags: tags)
}

/// Entry point using default options.
///
/// This is a drop-in replacement for `gleeunit.main()`. Call this from your
/// test file's `main` function if you don't need custom options.
pub fn main() -> Nil {
  run(defaults())
}

/// Run tests with the given options.
///
/// Discovers test files, applies CLI filters, shuffles with the
/// selected seed, executes, and prints results.
pub fn run(options: Options) -> Nil {
  let args = argv.load().arguments
  run_with_args(args, options)
}

/// Set a seed for reproducible test ordering.
pub fn seed(options: Options, seed: Int) -> Options {
  Options(..options, seed: option.Some(seed))
}

/// Set the default sort order for the table reporter.
pub fn sort_order(options: Options, sort_order: SortOrder) -> Options {
  Options(..options, sort_order:)
}

/// Reverse the default sort order for the table reporter.
///
/// The `--sort-rev` CLI flag toggles relative to this value: when set to
/// `True`, passing `--sort-rev` restores the unreversed order.
pub fn sort_reversed(options: Options, reversed: Bool) -> Options {
  Options(..options, sort_reversed: reversed)
}

/// Use the table reporter by default instead of the dot reporter.
pub fn table_reporter(options: Options) -> Options {
  Options(..options, reporter: TableReporter)
}

/// Mark a test with a single tag for filtering or skipping.
///
/// Use with Gleam's `use` syntax at the start of a test function.
/// Tags must be string literals: discovery reads them from source, and a
/// non-literal argument is ignored by filtering and reported with a warning.
pub fn tag(_tag: String, next: fn() -> a) -> a {
  next()
}

/// Mark a test with multiple tags for filtering or skipping.
///
/// Use with Gleam's `use` syntax at the start of a test function.
/// Tags must be string literals: discovery reads them from source, and
/// non-literal list elements are ignored by filtering and reported with a
/// warning.
pub fn tags(_tags: List(String), next: fn() -> a) -> a {
  next()
}

/// Set the per-test timeout. Tests exceeding it fail with a timeout error
/// instead of hanging. Defaults to 60 seconds. A non-positive duration
/// disables the timeout entirely.
///
/// On the JavaScript target, a test that *synchronously* hangs (an infinite
/// loop with no `await`) can only be interrupted in the parallel mode, which
/// runs tests in worker threads. The sequential and async modes run on the
/// main thread, where a synchronous hang blocks the event loop and the
/// timeout cannot fire.
pub fn timeout(options: Options, timeout: duration.Duration) -> Options {
  Options(..options, timeout:)
}

@internal
pub type CliAction {
  RunWithCliOptions(CliOptions)
  ShowCliMessage(message: String, exit_code: Int)
}

@internal
pub type LocationFilter {
  AllLocations
  OnlyTest(module: String, name: String)
  OnlyFile(path: String)
  OnlyFileAtLine(path: String, line: Int)
}

@internal
pub type Filter {
  Filter(location: LocationFilter, tag: Option(String))
}

@internal
pub type Reporter {
  DotReporter
  TableReporter
}

@internal
pub type CliOptions {
  CliOptions(
    seed: Option(Int),
    filter: Filter,
    no_color: Bool,
    reporter: Option(Reporter),
    sort_order: Option(SortOrder),
    sort_reversed: Bool,
    workers: Option(Int),
    timeout: Option(Int),
  )
}

@internal
pub fn parse_cli_args(args: List(String)) -> Result(CliOptions, String) {
  let command =
    clip.command({
      use seed_result <- clip.parameter
      use test_result <- clip.parameter
      use tag_result <- clip.parameter
      use no_color <- clip.parameter
      use reporter_result <- clip.parameter
      use sort_result <- clip.parameter
      use sort_rev <- clip.parameter
      use workers_result <- clip.parameter
      use timeout_result <- clip.parameter
      use file_result <- clip.parameter

      let seed = option.from_result(seed_result)
      let workers = option.from_result(workers_result)
      let timeout = option.from_result(timeout_result)
      #(
        file_result,
        seed,
        test_result,
        tag_result,
        no_color,
        reporter_result,
        sort_result,
        sort_rev,
        workers,
        timeout,
      )
    })
    |> clip.opt(
      opt.new("seed")
      |> opt.help("Set random seed for reproducible test ordering")
      |> opt.int
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("test")
      |> opt.help("Run a single test (format: wibble/wobble_test.name_test)")
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("tag")
      |> opt.help("Run tests with a specific tag")
      |> opt.optional,
    )
    |> clip.flag(flag.new("no-color") |> flag.help("Disable colored output"))
    |> clip.opt(
      opt.new("reporter")
      |> opt.help("Output format: dot (default) or table")
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("sort")
      |> opt.help("Sort order for table reporter: native, time, or name")
      |> opt.optional,
    )
    |> clip.flag(
      flag.new("sort-rev")
      |> flag.help(
        "Reverse the table sort order (toggles the configured sort_reversed default)",
      ),
    )
    |> clip.opt(
      opt.new("workers")
      |> opt.help("Run tests in parallel with this many workers")
      |> opt.int
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("timeout")
      |> opt.help("Per-test timeout in milliseconds (0 disables)")
      |> opt.int
      |> opt.optional,
    )
    |> clip.arg(
      arg.new("file")
      |> arg.help(
        "Run tests in a specific file (optionally with line number, e.g., file.gleam:10)",
      )
      |> arg.optional,
    )

  use
    #(
      file_result,
      seed,
      test_result,
      tag_result,
      no_color,
      reporter_result,
      sort_result,
      sort_rev,
      workers,
      timeout,
    )
  <- result.try(
    command
    |> clip.help(help.simple("unitest", "Simple unit testing framework"))
    |> clip.run(args),
  )

  use filter <- result.try(resolve_filter(test_result, file_result, tag_result))
  use reporter <- result.try(parse_reporter(reporter_result))
  use sort_order <- result.try(parse_sort_order(sort_result))
  use validated_workers <- result.try(validate_workers(workers))
  use validated_timeout <- result.try(validate_timeout(timeout))
  Ok(CliOptions(
    seed:,
    filter:,
    no_color:,
    reporter:,
    sort_order:,
    sort_reversed: sort_rev,
    workers: validated_workers,
    timeout: validated_timeout,
  ))
}

fn parse_reporter(
  reporter_result: Result(String, Nil),
) -> Result(Option(Reporter), String) {
  case reporter_result {
    Error(Nil) -> Ok(option.None)
    Ok("dot") -> Ok(option.Some(DotReporter))
    Ok("table") -> Ok(option.Some(TableReporter))
    Ok(other) ->
      Error("Invalid reporter: '" <> other <> "'. Use 'dot' or 'table'")
  }
}

fn parse_sort_order(
  sort_result: Result(String, Nil),
) -> Result(Option(SortOrder), String) {
  case sort_result {
    Error(Nil) -> Ok(option.None)
    Ok("native") -> Ok(option.Some(NativeSort))
    Ok("time") -> Ok(option.Some(TimeSort))
    Ok("name") -> Ok(option.Some(NameSort))
    Ok(other) ->
      Error(
        "Invalid sort order: '" <> other <> "'. Use 'native', 'time', or 'name'",
      )
  }
}

fn validate_workers(workers: Option(Int)) -> Result(Option(Int), String) {
  case workers {
    option.Some(n) if n <= 0 -> Error("Workers must be positive")
    option.Some(_) | option.None -> Ok(workers)
  }
}

fn validate_timeout(timeout: Option(Int)) -> Result(Option(Int), String) {
  case timeout {
    option.Some(n) if n < 0 -> Error("Timeout must be zero or positive")
    option.Some(_) | option.None -> Ok(timeout)
  }
}

fn resolve_filter(
  test_result: Result(String, Nil),
  file_result: Result(String, Nil),
  tag_result: Result(String, Nil),
) -> Result(Filter, String) {
  resolve_location(test_result, file_result)
  |> result.map(fn(location) {
    Filter(location:, tag: option.from_result(tag_result))
  })
}

fn resolve_location(
  test_result: Result(String, Nil),
  file_result: Result(String, Nil),
) -> Result(LocationFilter, String) {
  case test_result, file_result {
    Ok(test_str), _ -> parse_test_filter(test_str)
    _, Ok(file_str) -> parse_file_filter(file_str)
    _, _ -> Ok(AllLocations)
  }
}

fn parse_test_filter(test_str: String) -> Result(LocationFilter, String) {
  case string.split_once(test_str, ".") {
    Ok(#(module, name)) if module != "" && name != "" ->
      Ok(OnlyTest(module:, name:))
    _ ->
      Error(
        "Invalid --test format: '"
        <> test_str
        <> "'. Expected: module/path.function_name",
      )
  }
}

fn parse_file_filter(file_str: String) -> Result(LocationFilter, String) {
  let #(drive, rest) = split_drive_prefix(file_str)
  case string.split_once(rest, ":") {
    Ok(#(path, line_str)) ->
      case int.parse(line_str) {
        Ok(line) if line > 0 ->
          Ok(OnlyFileAtLine(path: normalize_separators(drive <> path), line:))
        Ok(_) ->
          Error(
            "Line number must be positive in file filter: '" <> line_str <> "'",
          )
        Error(_) ->
          Error("Invalid line number in file filter: '" <> line_str <> "'")
      }
    Error(Nil) -> Ok(OnlyFile(path: normalize_separators(file_str)))
  }
}

fn normalize_separators(path: String) -> String {
  string.replace(path, "\\", "/")
}

fn split_drive_prefix(path: String) -> #(String, String) {
  case string.to_graphemes(string.slice(path, 0, 3)) {
    [letter, ":", "/"] | [letter, ":", "\\"] ->
      case is_ascii_letter(letter) {
        True -> #(letter <> ":", string.drop_start(path, 2))
        False -> #("", path)
      }
    _ -> #("", path)
  }
}

fn is_ascii_letter(grapheme: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz", string.lowercase(grapheme))
}

@internal
pub fn resolve_cli_action(args: List(String)) -> CliAction {
  case parse_cli_args(args) {
    Ok(cli_opts) -> RunWithCliOptions(cli_opts)
    Error(message) ->
      case wants_help(args) {
        True -> ShowCliMessage(message, 0)
        False -> ShowCliMessage(message, 1)
      }
  }
}

fn wants_help(args: List(String)) -> Bool {
  list.contains(args, "--help") || list.contains(args, "-h")
}

@internal
pub fn render_table(
  results: List(TestResult),
  use_color: Bool,
  sort_order: SortOrder,
  sort_reversed: Bool,
) -> String {
  let sorted_results = sort_results(results, sort_order, sort_reversed)

  let header_row =
    ["Status", "Module", "Test", "Duration"]
    |> list.map(utils.maybe_color(_, use_color, ansi.bold))
  let builder =
    tobble.builder()
    |> tobble.add_row(header_row)

  let builder =
    list.fold(sorted_results, builder, fn(b, result) {
      let TestResult(item: test_, outcome:, duration:) = result
      let status = status_cell(outcome, use_color)
      tobble.add_row(b, [
        status,
        test_.module,
        test_.name,
        duration_cell(outcome, duration),
      ])
    })

  case tobble.build(builder) {
    Ok(table) -> tobble.render(table)
    Error(_) -> "Error: Failed to render results table."
  }
}

fn status_cell(outcome: Outcome, use_color: Bool) -> String {
  case outcome, use_color {
    Passed, True -> ansi.green("✓")
    Passed, False -> "PASS"
    Failed(_), True -> ansi.red("✗")
    Failed(_), False -> "FAIL"
    Skipped, True -> ansi.yellow("S")
    Skipped, False -> "SKIP"
  }
}

fn duration_cell(outcome: Outcome, elapsed: duration.Duration) -> String {
  case outcome {
    Skipped -> "-"
    Passed | Failed(_) -> utils.format_duration(elapsed)
  }
}

fn sort_results(
  results: List(TestResult),
  sort_order: SortOrder,
  sort_reversed: Bool,
) -> List(TestResult) {
  case sort_order, sort_reversed {
    NativeSort, False -> results
    NativeSort, True -> list.reverse(results)
    TimeSort, reversed ->
      list.sort(results, fn(a, b) { compare_by_time(a, b, reversed) })
    NameSort, False -> list.sort(results, compare_by_name)
    NameSort, True -> list.sort(results, order.reverse(compare_by_name))
  }
}

fn compare_by_name(a: TestResult, b: TestResult) -> order.Order {
  string.compare(a.item.module, b.item.module)
  |> order.lazy_break_tie(fn() { string.compare(a.item.name, b.item.name) })
}

fn compare_by_time(
  a: TestResult,
  b: TestResult,
  reversed: Bool,
) -> order.Order {
  case a.outcome, b.outcome {
    Skipped, Skipped -> order.Eq
    Skipped, Passed | Skipped, Failed(_) -> order.Gt
    Passed, Skipped | Failed(_), Skipped -> order.Lt
    Passed, Passed
    | Passed, Failed(_)
    | Failed(_), Passed
    | Failed(_), Failed(_)
    ->
      case reversed {
        False -> duration.compare(b.duration, a.duration)
        True -> duration.compare(a.duration, b.duration)
      }
  }
}

@internal
pub fn parse_package_name(content: String) -> Result(String, Nil) {
  content
  |> string.split("\n")
  |> list.find_map(parse_name_line)
}

fn parse_name_line(line: String) -> Result(String, Nil) {
  use #(key, value) <- result.try(string.split_once(line, "="))
  use <- bool.guard(when: string.trim(key) != "name", return: Error(Nil))
  case string.split(value, "\"") {
    [_, name, ..] -> Ok(name)
    _ -> Error(Nil)
  }
}

@internal
pub fn resolve_package_name(
  toml_result: Result(String, a),
) -> Result(String, String) {
  case toml_result {
    Ok(content) ->
      parse_package_name(content)
      |> result.replace_error("Error: Could not find 'name' in gleam.toml")
    Error(_) -> Error("Error: Could not read gleam.toml")
  }
}

fn get_package_name() -> Result(String, String) {
  simplifile.read("gleam.toml")
  |> resolve_package_name
}

const yield_every_n_tests = 5

const parallel_threshold = 50

@internal
pub type ResolvedExecutionMode {
  ResolvedSequential
  ResolvedAsync
  ResolvedParallel(workers: Int)
}

@internal
pub type PlanItem {
  Run(discovery.Test)
  Skip(discovery.Test)
}

@internal
pub type Outcome {
  Passed
  Failed(reason: TestFailure)
  Skipped
}

@internal
pub type TestResult {
  TestResult(
    item: discovery.Test,
    outcome: Outcome,
    duration: duration.Duration,
  )
}

@internal
pub type FailureRecord {
  FailureRecord(
    item: discovery.Test,
    error: TestFailure,
    duration: duration.Duration,
  )
}

@internal
pub type Report {
  Report(
    passed: Int,
    failed: Int,
    skipped: Int,
    failures: List(FailureRecord),
    seed: Int,
    runtime: duration.Duration,
  )
}

@internal
pub type Platform {
  Platform(
    now_ms: fn() -> Int,
    run_test: fn(discovery.Test, fn(Outcome) -> Nil) -> Nil,
    start_module_pool: fn(List(List(discovery.Test)), Int) -> Nil,
    receive_pool_result: fn(fn(TestResult) -> Nil) -> Nil,
  )
}

@internal
pub type Progress {
  Progress(current: Int, total: Int)
}

@internal
pub type ExecuteResult {
  ExecuteResult(report: Report, results: List(TestResult))
}

type ExecutionConfig {
  ExecutionConfig(
    seed: Int,
    mode: ResolvedExecutionMode,
    use_color: Bool,
    reporter: Reporter,
    sort_order: SortOrder,
    sort_reversed: Bool,
    check_results: Bool,
    timeout_ms: Int,
  )
}

type OnResultCallback =
  fn(TestResult, Progress, fn() -> Nil) -> Nil

type ExecutionState {
  ExecutionState(results: List(TestResult), completed: Int)
}

type ExecutionContext {
  ExecutionContext(
    total: Int,
    platform: Platform,
    on_result: OnResultCallback,
    finish: fn(ExecutionState) -> Nil,
  )
}

@internal
pub fn execute_pooled(
  plan: List(PlanItem),
  seed: Int,
  workers: Int,
  platform: Platform,
  on_result: OnResultCallback,
  on_complete: fn(ExecuteResult) -> Nil,
) -> Nil {
  let total = list.length(plan)
  let start_ms = platform.now_ms()

  let tests = runnable_tests(plan)
  let remaining = list.length(tests)

  let finish = fn(final_state) {
    finalize(final_state, seed, start_ms, platform, on_complete)
  }
  let ctx = ExecutionContext(total:, platform:, on_result:, finish:)

  case tests {
    [] -> emit_skips(plan, initial_state(), ctx, finish)
    _ -> {
      let module_groups = list.chunk(tests, by: fn(t) { t.module })
      platform.start_module_pool(module_groups, workers)
      emit_skips(plan, initial_state(), ctx, fn(skip_state) {
        receive_loop(remaining, skip_state, ctx)
      })
    }
  }
}

fn receive_loop(
  remaining: Int,
  state: ExecutionState,
  ctx: ExecutionContext,
) -> Nil {
  case remaining {
    0 -> ctx.finish(state)
    _ -> {
      ctx.platform.receive_pool_result(fn(pool_result) {
        let #(result, new_state) =
          process_run_result(
            pool_result.item,
            pool_result.outcome,
            pool_result.duration,
            state,
          )
        deliver_result(result, new_state, ctx, fn(new_state) {
          receive_loop(remaining - 1, new_state, ctx)
        })
      })
    }
  }
}

fn emit_skips(
  plan: List(PlanItem),
  state: ExecutionState,
  ctx: ExecutionContext,
  continue: fn(ExecutionState) -> Nil,
) -> Nil {
  case plan {
    [] -> continue(state)
    [Skip(t), ..rest] ->
      emit_skip(t, state, ctx, fn(new_state) {
        emit_skips(rest, new_state, ctx, continue)
      })
    [Run(_), ..rest] -> emit_skips(rest, state, ctx, continue)
  }
}

fn emit_skip(
  test_: discovery.Test,
  state: ExecutionState,
  ctx: ExecutionContext,
  continue: fn(ExecutionState) -> Nil,
) -> Nil {
  let #(result, new_state) = apply_skip(test_, state)
  deliver_result(result, new_state, ctx, continue)
}

fn deliver_result(
  result: TestResult,
  state: ExecutionState,
  ctx: ExecutionContext,
  continue: fn(ExecutionState) -> Nil,
) -> Nil {
  let progress = Progress(current: state.completed, total: ctx.total)
  ctx.on_result(result, progress, fn() { continue(state) })
}

fn runnable_tests(plan: List(PlanItem)) -> List(discovery.Test) {
  list.filter_map(plan, fn(item) {
    case item {
      Run(t) -> Ok(t)
      Skip(_) -> Error(Nil)
    }
  })
}

fn initial_state() -> ExecutionState {
  ExecutionState(results: [], completed: 0)
}

fn finalize(
  state: ExecutionState,
  seed: Int,
  start_ms: Int,
  platform: Platform,
  on_complete: fn(ExecuteResult) -> Nil,
) -> Nil {
  let runtime = duration.milliseconds(platform.now_ms() - start_ms)
  let report = build_report(state, seed, runtime)
  on_complete(ExecuteResult(report:, results: list.reverse(state.results)))
}

fn build_report(
  state: ExecutionState,
  seed: Int,
  runtime: duration.Duration,
) -> Report {
  let results = list.reverse(state.results)
  let failures =
    list.filter_map(results, fn(r) {
      case r.outcome {
        Failed(error) ->
          Ok(FailureRecord(item: r.item, error:, duration: r.duration))
        Passed | Skipped -> Error(Nil)
      }
    })
  Report(
    passed: list.count(results, fn(r) { r.outcome == Passed }),
    failed: list.length(failures),
    skipped: list.count(results, fn(r) { r.outcome == Skipped }),
    failures:,
    seed:,
    runtime:,
  )
}

fn process_run_result(
  test_: discovery.Test,
  outcome: Outcome,
  elapsed: duration.Duration,
  state: ExecutionState,
) -> #(TestResult, ExecutionState) {
  let test_result =
    TestResult(
      item: test_,
      outcome: ensure_location(outcome, test_),
      duration: elapsed,
    )
  #(test_result, add_result(state, test_result))
}

/// Failures from crashes, timeouts, and decode fallbacks carry no source
/// location. Fall back to the test function's own location from discovery.
fn ensure_location(outcome: Outcome, test_: discovery.Test) -> Outcome {
  case outcome {
    Failed(error) -> Failed(backfill_location(error, test_))
    Passed | Skipped -> outcome
  }
}

fn backfill_location(error: TestFailure, test_: discovery.Test) -> TestFailure {
  case error.file, error.line {
    "", _ | _, 0 ->
      test_failure.TestFailure(
        ..error,
        file: test_.file_path,
        line: test_.line_span.start_line,
      )
    _, _ -> error
  }
}

fn apply_skip(
  test_: discovery.Test,
  state: ExecutionState,
) -> #(TestResult, ExecutionState) {
  let result =
    TestResult(item: test_, outcome: Skipped, duration: duration.seconds(0))
  #(result, add_result(state, result))
}

fn add_result(state: ExecutionState, result: TestResult) -> ExecutionState {
  ExecutionState(
    results: [result, ..state.results],
    completed: state.completed + 1,
  )
}

@internal
pub fn execute_sequential(
  plan: List(PlanItem),
  seed: Int,
  platform: Platform,
  on_result: OnResultCallback,
  on_complete: fn(ExecuteResult) -> Nil,
) -> Nil {
  let start_ms = platform.now_ms()
  let finish = fn(final_state) {
    finalize(final_state, seed, start_ms, platform, on_complete)
  }
  let ctx =
    ExecutionContext(total: list.length(plan), platform:, on_result:, finish:)

  execute_loop(plan, initial_state(), ctx)
}

fn execute_loop(
  plan: List(PlanItem),
  state: ExecutionState,
  ctx: ExecutionContext,
) -> Nil {
  case plan {
    [] -> ctx.finish(state)
    [Skip(t), ..rest] ->
      emit_skip(t, state, ctx, fn(new_state) {
        execute_loop(rest, new_state, ctx)
      })
    [Run(t), ..rest] -> {
      let start = ctx.platform.now_ms()
      ctx.platform.run_test(t, fn(run_result) {
        let elapsed = duration.milliseconds(ctx.platform.now_ms() - start)
        let #(result, new_state) =
          process_run_result(t, run_result, elapsed, state)
        deliver_result(result, new_state, ctx, fn(new_state) {
          execute_loop(rest, new_state, ctx)
        })
      })
    }
  }
}

@internal
pub fn exit_code(report: Report) -> Int {
  case report.failed > 0 {
    True -> 1
    False -> 0
  }
}

@internal
pub fn outcome_char(outcome: Outcome, use_color: Bool) -> String {
  case outcome {
    Passed -> utils.maybe_color(".", use_color, ansi.green)
    Failed(_) -> utils.maybe_color("F", use_color, ansi.red)
    Skipped -> utils.maybe_color("S", use_color, ansi.yellow)
  }
}

@internal
pub fn plan(
  tests: List(discovery.Test),
  cli_opts: CliOptions,
  ignored_tags: List(String),
) -> List(PlanItem) {
  list.filter_map(tests, fn(t) {
    case should_include(t, cli_opts.filter) {
      False -> Error(Nil)
      True -> Ok(to_plan_item(t, cli_opts.filter, ignored_tags))
    }
  })
}

fn should_include(t: discovery.Test, filter: Filter) -> Bool {
  let location_match = case filter.location {
    AllLocations -> True
    OnlyTest(module, name) -> t.module == module && t.name == name
    OnlyFile(path) -> path_matches(t.file_path, path)
    OnlyFileAtLine(path, line) ->
      path_matches(t.file_path, path) && line_in_span(line, t.line_span)
  }

  let tag_match = case filter.tag {
    option.None -> True
    option.Some(tag) -> list.contains(t.tags, tag)
  }

  location_match && tag_match
}

fn path_matches(test_path: String, filter_path: String) -> Bool {
  test_path == filter_path
  || string.ends_with(test_path, "/" <> filter_path)
  || string.ends_with(filter_path, "/" <> test_path)
}

fn line_in_span(line: Int, span: discovery.LineSpan) -> Bool {
  line >= span.start_line && line <= span.end_line
}

fn to_plan_item(
  test_: discovery.Test,
  filter: Filter,
  ignored_tags: List(String),
) -> PlanItem {
  let has_ignored_tag =
    list.any(test_.tags, fn(tag) { list.contains(ignored_tags, tag) })

  let should_skip = case filter.tag, filter.location {
    option.Some(_), _
    | option.None, OnlyTest(_, _)
    | option.None, OnlyFileAtLine(_, _)
    -> False
    option.None, AllLocations | option.None, OnlyFile(_) -> has_ignored_tag
  }

  case should_skip {
    True -> Skip(test_)
    False -> Run(test_)
  }
}

@internal
pub fn render_summary(report: Report, use_color: Bool) -> String {
  let status_line = format_status(report.passed, report.failed, use_color)
  let skipped_line = format_skipped(report.skipped, use_color)
  let seed_line = "Seed: " <> int.to_string(report.seed)
  let time_line = "Finished in " <> utils.format_duration(report.runtime)

  let failure_details = case report.failures {
    [] -> ""
    failures -> "\n\nFailures:\n" <> render_failures(failures, use_color)
  }

  ["\n", status_line <> skipped_line, time_line, seed_line, failure_details]
  |> utils.join_present("\n")
}

fn format_status(passed: Int, failed: Int, use_color: Bool) -> String {
  let text = case failed {
    0 -> int.to_string(passed) <> " passed, no failures"
    1 -> int.to_string(passed) <> " passed, 1 failure"
    _ ->
      int.to_string(passed)
      <> " passed, "
      <> int.to_string(failed)
      <> " failures"
  }

  let colorize = case failed {
    0 -> ansi.green
    _ -> ansi.red
  }
  utils.maybe_color(text, use_color, colorize)
}

fn format_skipped(skipped: Int, use_color: Bool) -> String {
  use <- bool.guard(when: skipped == 0, return: "")
  let text = ", " <> int.to_string(skipped) <> " skipped"
  utils.maybe_color(text, use_color, ansi.yellow)
}

fn render_failures(failures: List(FailureRecord), use_color: Bool) -> String {
  failures
  |> list.index_map(fn(failure, index) {
    let source = case failure.error.kind {
      test_failure.Assert(start:, end:, ..)
      | test_failure.LetAssert(start:, end:, ..) ->
        test_failure.extract_snippet(failure.error.file, start, end)
        |> option.from_result
      test_failure.Panic
      | test_failure.Todo
      | test_failure.Timeout(..)
      | test_failure.Crashed(..)
      | test_failure.Undef(..)
      | test_failure.Generic -> option.None
    }

    test_failure.format_failure(
      index: index + 1,
      module: failure.item.module,
      name: failure.item.name,
      duration: failure.duration,
      error: failure.error,
      source:,
      use_color:,
    )
  })
  |> string.join("\n\n")
}

@internal
pub fn resolve_execution_mode(
  cli_workers cli_workers: Option(Int),
  option_mode option_mode: ExecutionMode,
  runtime_default runtime_default: Int,
  runnable_count runnable_count: Int,
) -> ResolvedExecutionMode {
  case cli_workers {
    option.Some(n) -> ResolvedParallel(n)
    option.None ->
      case option_mode {
        RunSequential -> ResolvedSequential
        RunAsync -> ResolvedAsync
        RunParallel(n) -> ResolvedParallel(n)
        RunParallelAuto ->
          case runnable_count < parallel_threshold {
            True -> ResolvedSequential
            False -> ResolvedParallel(runtime_default)
          }
      }
  }
}

fn run_with_args(args: List(String), options: Options) -> Nil {
  case resolve_cli_action(args) {
    RunWithCliOptions(cli_opts) -> run_with_cli_opts(cli_opts, options)
    ShowCliMessage(message, exit_code) -> {
      io.println_error(message)

      case exit_code {
        0 -> Nil
        _ -> halt(exit_code)
      }
    }
  }
}

fn run_with_cli_opts(cli_opts: CliOptions, options: Options) -> Nil {
  let use_color = should_use_color(cli_opts.no_color)

  case discovery.from_fs() {
    Error(error) -> {
      io.println_error(
        "Could not read test directory: " <> simplifile.describe_error(error),
      )
      halt(1)
    }
    Ok(discovered) -> {
      case discovered.failed_paths {
        [] -> Nil
        failed_paths -> io.println_error(parse_failure_message(failed_paths))
      }

      case discovered.tag_warnings {
        [] -> Nil
        warnings -> io.println_error(tag_warning_message(warnings))
      }

      run_discovered(cli_opts, options, use_color, discovered.tests)
    }
  }
}

fn tag_warning_message(locations: List(String)) -> String {
  "Warning: non-literal tags are ignored by tag filtering:\n"
  <> indented_lines(locations)
}

fn indented_lines(items: List(String)) -> String {
  items
  |> list.map(fn(item) { "  " <> item })
  |> string.join("\n")
}

fn parse_failure_message(paths: List(String)) -> String {
  "Warning: could not parse test files (their tests were skipped):\n"
  <> indented_lines(paths)
}

fn should_use_color(cli_no_color: Bool) -> Bool {
  !cli_no_color && result.is_error(envoy.get("NO_COLOR"))
}

fn run_discovered(
  cli_opts: CliOptions,
  options: Options,
  use_color: Bool,
  tests: List(discovery.Test),
) -> Nil {
  use <- bool.lazy_guard(when: list.is_empty(tests), return: fn() {
    io.println_error("No tests found in test/")
    halt(1)
  })

  let chosen_seed =
    option.or(cli_opts.seed, options.seed)
    |> option.lazy_unwrap(fn() { int.random(2_147_483_647) })

  let sorted =
    list.sort(tests, fn(a, b) {
      string.compare(a.module, b.module)
      |> order.break_tie(string.compare(a.name, b.name))
    })
  let groups = list.chunk(sorted, by: fn(t) { t.module })
  let seed = random.new_seed(chosen_seed)
  let #(shuffled, _) = random.step(shuffle_by_groups(groups), seed)

  let plan = plan(shuffled, cli_opts, options.ignored_tags)

  use <- bool.lazy_guard(when: list.is_empty(plan), return: fn() {
    io.println_error(no_match_message(cli_opts.filter))
    halt(1)
  })

  let reporter = option.unwrap(cli_opts.reporter, options.reporter)
  let sort_order = option.unwrap(cli_opts.sort_order, options.sort_order)
  let sort_reversed =
    bool.exclusive_or(cli_opts.sort_reversed, options.sort_reversed)

  let runnable_count = list.count(plan, is_run)

  let mode =
    resolve_execution_mode(
      cli_workers: cli_opts.workers,
      option_mode: options.execution_mode,
      runtime_default: default_workers(),
      runnable_count:,
    )

  let timeout_ms =
    option.unwrap(cli_opts.timeout, duration.to_milliseconds(options.timeout))

  execute_and_finish(
    plan,
    ExecutionConfig(
      seed: chosen_seed,
      mode:,
      use_color:,
      reporter:,
      sort_order:,
      sort_reversed:,
      check_results: options.check_results,
      timeout_ms:,
    ),
  )
}

@internal
pub fn no_match_message(filter: Filter) -> String {
  "No tests matched " <> describe_filter(filter)
}

fn describe_filter(filter: Filter) -> String {
  [describe_location(filter.location), describe_tag(filter.tag)]
  |> utils.join_present(" and ")
}

fn describe_location(location: LocationFilter) -> String {
  case location {
    AllLocations -> ""
    OnlyTest(module:, name:) -> "test " <> module <> "." <> name
    OnlyFile(path:) -> "file " <> path
    OnlyFileAtLine(path:, line:) ->
      "file " <> path <> ":" <> int.to_string(line)
  }
}

fn describe_tag(tag: Option(String)) -> String {
  case tag {
    option.None -> ""
    option.Some(tag) -> "tag " <> tag
  }
}

fn shuffle_by_groups(groups: List(List(a))) -> random.Generator(List(a)) {
  random.shuffle(groups)
  |> random.then(fn(shuffled_groups) {
    list.fold(shuffled_groups, random.constant([]), fn(acc, group) {
      acc
      |> random.then(fn(a) {
        random.shuffle(group)
        |> random.map(list.append(a, _))
      })
    })
  })
}

fn is_run(item: PlanItem) -> Bool {
  case item {
    Run(_) -> True
    Skip(_) -> False
  }
}

fn execute_and_finish(plan: List(PlanItem), config: ExecutionConfig) -> Nil {
  let ExecutionConfig(
    seed:,
    mode:,
    use_color:,
    reporter:,
    sort_order:,
    sort_reversed:,
    check_results:,
    timeout_ms:,
  ) = config
  case get_package_name() {
    Error(error) -> {
      io.println_error(error)
      halt(1)
    }
    Ok(package_name) -> {
      let pool_starter = case mode {
        ResolvedAsync -> start_async_pool
        ResolvedSequential | ResolvedParallel(_) -> start_module_pool
      }
      let platform =
        Platform(
          now_ms:,
          run_test: fn(t, k) {
            run_test_async(t, package_name, check_results, timeout_ms, k)
          },
          start_module_pool: fn(module_groups, pool_workers) {
            pool_starter(
              module_groups,
              package_name,
              check_results,
              timeout_ms,
              pool_workers,
            )
          },
          receive_pool_result:,
        )

      let #(on_result, cleanup) =
        build_on_result_callback(reporter, use_color, sort_order, sort_reversed)

      let on_complete = fn(exec_result: ExecuteResult) {
        cleanup(exec_result)
        io.println(render_summary(exec_result.report, use_color))
        halt(exit_code(exec_result.report))
      }

      case mode {
        ResolvedSequential ->
          execute_sequential(plan, seed, platform, on_result, on_complete)
        ResolvedAsync ->
          execute_pooled(plan, seed, 1, platform, on_result, on_complete)
        ResolvedParallel(workers) ->
          execute_pooled(plan, seed, workers, platform, on_result, on_complete)
      }
    }
  }
}

fn build_on_result_callback(
  reporter: Reporter,
  use_color: Bool,
  sort_order: SortOrder,
  sort_reversed: Bool,
) -> #(OnResultCallback, fn(ExecuteResult) -> Nil) {
  case reporter {
    DotReporter -> {
      let on_result = fn(result: TestResult, _progress: Progress, continue) {
        io.print(outcome_char(result.outcome, use_color))
        continue()
      }
      let cleanup = fn(_: ExecuteResult) { Nil }
      #(on_result, cleanup)
    }
    TableReporter -> {
      let progress_spinner =
        spinner.new("Running tests...")
        |> spinner.with_colour(ansi.cyan)
        |> spinner.start

      let on_result = fn(_result: TestResult, progress: Progress, continue) {
        let text =
          "Running tests... "
          <> int.to_string(progress.current)
          <> "/"
          <> int.to_string(progress.total)
        spinner.set_text(progress_spinner, text)

        case progress.current % yield_every_n_tests == 0 {
          True -> yield_then(continue)
          False -> continue()
        }
      }

      let cleanup = fn(exec_result: ExecuteResult) {
        spinner.stop(progress_spinner)
        io.print(render_table(
          exec_result.results,
          use_color,
          sort_order,
          sort_reversed,
        ))
      }

      #(on_result, cleanup)
    }
  }
}

@external(erlang, "unitest_ffi", "default_workers")
@external(javascript, "./unitest_ffi.mjs", "defaultWorkers")
fn default_workers() -> Int

@external(erlang, "erlang", "halt")
@external(javascript, "./unitest_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

@external(erlang, "unitest_ffi", "now_ms")
@external(javascript, "./unitest_ffi.mjs", "nowMs")
fn now_ms() -> Int

@external(erlang, "unitest_ffi", "receive_pool_result")
@external(javascript, "./unitest_ffi.mjs", "receivePoolResult")
fn receive_pool_result(callback: fn(TestResult) -> Nil) -> Nil

@external(erlang, "unitest_ffi", "run_test_async")
@external(javascript, "./unitest_ffi.mjs", "runTestAsync")
fn run_test_async(
  test_: discovery.Test,
  package_name: String,
  check_results: Bool,
  timeout_ms: Int,
  k: fn(Outcome) -> Nil,
) -> Nil

@external(erlang, "unitest_ffi", "skip")
@external(javascript, "./unitest_ffi.mjs", "skip")
fn skip() -> a

@external(erlang, "unitest_ffi", "start_module_pool")
@external(javascript, "./unitest_ffi.mjs", "startAsyncPool")
fn start_async_pool(
  module_groups: List(List(discovery.Test)),
  package_name: String,
  check_results: Bool,
  timeout_ms: Int,
  workers: Int,
) -> Nil

@external(erlang, "unitest_ffi", "start_module_pool")
@external(javascript, "./unitest_ffi.mjs", "startModulePool")
fn start_module_pool(
  module_groups: List(List(discovery.Test)),
  package_name: String,
  check_results: Bool,
  timeout_ms: Int,
  workers: Int,
) -> Nil

@target(erlang)
fn yield_then(next: fn() -> Nil) -> Nil {
  next()
}

@target(javascript)
@external(javascript, "./unitest_ffi.mjs", "yieldThen")
fn yield_then(next: fn() -> Nil) -> Nil
