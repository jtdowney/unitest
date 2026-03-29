//// Unitest is a drop-in replacement for gleeunit that adds random test
//// ordering (with reproducible seeds), tagging, and CLI filtering.

import argv
import envoy
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/string
import gleam_community/ansi
import prng/random
import simplifile
import spinner
import unitest/internal/cli
import unitest/internal/discover
import unitest/internal/format_table
import unitest/internal/runner

const yield_every_n_tests = 5

const parallel_threshold = 50

/// Controls how tests are executed.
pub type ExecutionMode {
  /// Runs one test at a time.
  RunSequential
  /// Runs tests concurrently within each module.
  RunAsync
  /// Runs the given number of module groups simultaneously, each with
  /// per-module concurrency up to the CPU core count.
  RunParallel(workers: Int)
  /// Auto-detects the number of module-group workers. Falls back to
  /// sequential when the test count is below the parallel threshold.
  RunParallelAuto
}

@internal
pub type ResolvedExecutionMode {
  ResolvedSequential
  ResolvedAsync
  ResolvedParallel(workers: Int)
}

@internal
pub type CliAction {
  RunWithCliOptions(cli.Options)
  ShowCliMessage(message: String, exit_code: Int)
}

/// Configuration for the test runner.
///
/// Tests with any `ignored_tags` are skipped and reported as `S`.
/// When `check_results` is `True`, tests returning `Error(reason)`
/// are treated as failures (default `False`).
///
/// ## Example
///
/// ```gleam
/// unitest.run(Options(
///   ..unitest.default_options(),
///   ignored_tags: ["slow"],
///   execution_mode: RunParallelAuto,
/// ))
/// ```
pub type Options {
  Options(
    seed: Option(Int),
    ignored_tags: List(String),
    test_directory: String,
    sort_order: cli.SortOrder,
    sort_reversed: Bool,
    check_results: Bool,
    execution_mode: ExecutionMode,
  )
}

/// Returns default options with no seed and no ignored tags.
pub fn default_options() -> Options {
  Options(
    seed: option.None,
    ignored_tags: [],
    test_directory: "test",
    sort_order: cli.NativeSort,
    sort_reversed: False,
    check_results: False,
    execution_mode: RunSequential,
  )
}

/// Run tests with the given options.
///
/// Discovers test files, applies CLI filters, shuffles with the
/// selected seed, executes, and prints results.
///
/// ## CLI Arguments
///
/// Pass arguments after `--` when running `gleam test`:
///
/// - `<file>` or `<file>:<line>`: Run tests in a file, optionally at a line
/// - `--test <module.fn>`: Run a single test function
/// - `--tag <name>`: Run only tests with this tag
/// - `--seed <int>`: Reproducible ordering
/// - `--reporter <dot|table>`: Output format (default: dot)
/// - `--sort <native|time|name>`: Sort order for table reporter
/// - `--sort-rev`: Reverse sort order
/// - `--workers <int>`: Parallel module-group workers
/// - `--no-color`: Disable colored output
///
/// ## Example
///
/// ```gleam
/// pub fn main() {
///   unitest.run(Options(..unitest.default_options(), ignored_tags: ["slow"]))
/// }
/// ```
pub fn run(options: Options) -> Nil {
  let args = argv.load().arguments
  run_with_args(args, options)
}

/// Entry point using default options.
///
/// This is a drop-in replacement for `gleeunit.main()`. Call this from your
/// test file's `main` function if you don't need custom options.
///
/// ## Example
///
/// ```gleam
/// pub fn main() {
///   unitest.main()
/// }
/// ```
pub fn main() -> Nil {
  run(default_options())
}

/// Mark a test with a single tag for filtering or skipping.
///
/// Use with Gleam's `use` syntax at the start of a test function.
/// Tags must be string literals for static analysis.
///
/// ## Example
///
/// ```gleam
/// pub fn database_integration_test() {
///   use <- unitest.tag("integration")
///   // test code here
/// }
/// ```
///
/// Then run: `gleam test -- --tag integration`
pub fn tag(_tag: String, next: fn() -> a) -> a {
  next()
}

/// Mark a test with multiple tags for filtering or skipping.
///
/// Use with Gleam's `use` syntax at the start of a test function.
/// Tags must be string literals for static analysis.
///
/// ## Example
///
/// ```gleam
/// pub fn slow_integration_test() {
///   use <- unitest.tags(["slow", "integration"])
///   // test code here
/// }
/// ```
pub fn tags(_tags: List(String), next: fn() -> a) -> a {
  next()
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
pub fn guard(condition: Bool, next: fn() -> a) -> a {
  bool.lazy_guard(when: !condition, return: skip, otherwise: next)
}

@external(erlang, "unitest_ffi", "skip")
@external(javascript, "./unitest_ffi.mjs", "skip")
fn skip() -> a

@internal
pub fn resolve_execution_mode(
  cli_workers: Option(Int),
  option_mode: ExecutionMode,
  runtime_default: Int,
) -> ResolvedExecutionMode {
  case cli_workers {
    option.Some(n) -> ResolvedParallel(n)
    option.None ->
      case option_mode {
        RunSequential -> ResolvedSequential
        RunAsync -> ResolvedAsync
        RunParallel(n) -> ResolvedParallel(n)
        RunParallelAuto -> ResolvedParallel(runtime_default)
      }
  }
}

@external(erlang, "unitest_ffi", "default_workers")
@external(javascript, "./unitest_ffi.mjs", "defaultWorkers")
fn default_workers() -> Int

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

@internal
pub fn resolve_cli_action(args: List(String)) -> CliAction {
  case cli.parse(args) {
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

fn run_with_cli_opts(cli_opts: cli.Options, options: Options) -> Nil {
  let use_color = should_use_color(cli_opts.no_color)
  let tests = discover.discover_from_fs(options.test_directory)

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

  let plan = runner.plan(shuffled, cli_opts, options.ignored_tags)

  let sort_order = option.unwrap(cli_opts.sort_order, options.sort_order)
  let sort_reversed =
    bool.exclusive_or(cli_opts.sort_reversed, options.sort_reversed)

  let runnable_count =
    list.count(plan, fn(item) {
      case item {
        runner.Run(_) -> True
        runner.Skip(_) -> False
      }
    })

  let mode =
    resolve_execution_mode(
      cli_opts.workers,
      options.execution_mode,
      default_workers(),
    )
    |> apply_parallel_threshold(
      runnable_count,
      options.execution_mode,
      cli_opts.workers,
    )

  execute_and_finish(
    plan,
    chosen_seed,
    mode,
    use_color,
    cli_opts.reporter,
    sort_order,
    sort_reversed,
    options.check_results,
  )
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

@internal
pub fn apply_parallel_threshold(
  mode: ResolvedExecutionMode,
  runnable_count: Int,
  option_mode: ExecutionMode,
  cli_workers: Option(Int),
) -> ResolvedExecutionMode {
  use <- bool.guard(when: option.is_some(cli_workers), return: mode)
  case option_mode, mode {
    RunParallelAuto, ResolvedParallel(_) if runnable_count < parallel_threshold ->
      ResolvedAsync
    _, _ -> mode
  }
}

fn execute_and_finish(
  plan: List(runner.PlanItem),
  seed: Int,
  mode: ResolvedExecutionMode,
  use_color: Bool,
  reporter: cli.Reporter,
  sort_order: cli.SortOrder,
  sort_reversed: Bool,
  check_results: Bool,
) -> Nil {
  case get_package_name() {
    Error(error) -> {
      io.println_error(error)
      halt(1)
    }
    Ok(package_name) -> {
      let platform =
        runner.Platform(
          now_ms: now_ms,
          run_test: fn(t, k) {
            run_test_async(t, package_name, check_results, k)
          },
          start_module_pool: fn(module_groups, pool_workers) {
            start_module_pool(
              module_groups,
              package_name,
              check_results,
              pool_workers,
            )
          },
          receive_pool_result: receive_pool_result,
          print: io.print,
        )

      let #(on_result, cleanup) =
        build_on_result_callback(reporter, use_color, sort_order, sort_reversed)

      let on_complete = fn(exec_result: runner.ExecuteResult) {
        cleanup(exec_result)
        io.println(runner.render_summary(exec_result.report, use_color))
        halt(exit_code(exec_result.report))
      }

      case mode {
        ResolvedSequential ->
          runner.execute_sequential(
            plan,
            seed,
            platform,
            on_result,
            on_complete,
          )
        ResolvedAsync ->
          runner.execute_pooled(plan, seed, 1, platform, on_result, on_complete)
        ResolvedParallel(workers) ->
          runner.execute_pooled(
            plan,
            seed,
            workers,
            platform,
            on_result,
            on_complete,
          )
      }
    }
  }
}

type OnResultCallback =
  fn(runner.TestResult, runner.Progress, fn() -> Nil) -> Nil

type CleanupCallback =
  fn(runner.ExecuteResult) -> Nil

fn build_on_result_callback(
  reporter: cli.Reporter,
  use_color: Bool,
  sort_order: cli.SortOrder,
  sort_reversed: Bool,
) -> #(OnResultCallback, CleanupCallback) {
  case reporter {
    cli.DotReporter -> {
      let on_result = fn(
        result: runner.TestResult,
        _progress: runner.Progress,
        continue,
      ) {
        io.print(runner.outcome_char(result.outcome, use_color))
        continue()
      }
      let cleanup = fn(_: runner.ExecuteResult) { Nil }
      #(on_result, cleanup)
    }
    cli.TableReporter -> {
      let progress_spinner =
        spinner.new("Running tests...")
        |> spinner.with_colour(ansi.cyan)
        |> spinner.start

      let on_result = fn(
        _result: runner.TestResult,
        progress: runner.Progress,
        continue,
      ) {
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

      let cleanup = fn(exec_result: runner.ExecuteResult) {
        spinner.stop(progress_spinner)
        io.print(format_table.render_table(
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

@internal
pub fn exit_code(report: runner.Report) -> Int {
  case report.failed > 0 {
    True -> 1
    False -> 0
  }
}

fn should_use_color(cli_no_color: Bool) -> Bool {
  !cli_no_color && result.is_error(envoy.get("NO_COLOR"))
}

@external(erlang, "unitest_ffi", "now_ms")
@external(javascript, "./unitest_ffi.mjs", "nowMs")
fn now_ms() -> Int

@external(erlang, "unitest_ffi", "run_test_async")
@external(javascript, "./unitest_ffi.mjs", "runTestAsync")
fn run_test_async(
  t: discover.Test,
  package_name: String,
  check_results: Bool,
  k: fn(runner.TestRunResult) -> Nil,
) -> Nil

@external(erlang, "unitest_ffi", "start_module_pool")
@external(javascript, "./unitest_ffi.mjs", "startModulePool")
fn start_module_pool(
  module_groups: List(List(discover.Test)),
  package_name: String,
  check_results: Bool,
  workers: Int,
) -> Nil

@external(erlang, "unitest_ffi", "receive_pool_result")
@external(javascript, "./unitest_ffi.mjs", "receivePoolResult")
fn receive_pool_result(callback: fn(runner.PoolResult) -> Nil) -> Nil

@target(erlang)
fn yield_then(next: fn() -> Nil) -> Nil {
  next()
}

@target(javascript)
@external(javascript, "./unitest_ffi.mjs", "yieldThen")
fn yield_then(next: fn() -> Nil) -> Nil

@external(erlang, "erlang", "halt")
@external(javascript, "./unitest_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

fn get_package_name() -> Result(String, String) {
  simplifile.read("gleam.toml")
  |> resolve_package_name
}

@internal
pub fn parse_package_name(content: String) -> Result(String, Nil) {
  content
  |> string.split("\n")
  |> list.find_map(fn(line) {
    let trimmed = string.trim_start(line)
    case string.starts_with(trimmed, "name") {
      False -> Error(Nil)
      True ->
        case string.split(trimmed, "\"") {
          [_, name, ..] -> Ok(name)
          _ -> Error(Nil)
        }
    }
  })
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
