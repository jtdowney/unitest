//// Unitest is a Gleam test runner with random ordering, tagging, and CLI filtering.
////
//// Drop-in replacement for gleeunit with additional features:
//// - Random test ordering with reproducible seeds
//// - Test tagging for selective execution
//// - CLI filtering by module, test, or tag

import argv
import envoy
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam/result
import gleam/string
import gleam_community/ansi
import simplifile
import spinner
import unitest/internal/cli.{
  type Reporter, type SortOrder, DotReporter, TableReporter,
}
import unitest/internal/discover.{type Test}
import unitest/internal/format_table
import unitest/internal/runner.{type Progress, type Report, type TestResult}

const yield_every_n_tests = 5

/// Configuration options for the test runner.
///
/// ## Fields
///
/// - `seed`: Optional seed for deterministic test ordering. When `None`,
///   a random seed is generated automatically.
/// - `ignored_tags`: Tests with any of these tags will be skipped and
///   reported as `S` in the output.
/// - `test_directory`: Directory containing test files.
/// - `sort_order`: Default sort order for table reporter output.
/// - `sort_reversed`: Whether to reverse the sort order.
///
/// ## Example
///
/// ```gleam
/// unitest.run(Options(
///   seed: Some(12345),
///   ignored_tags: ["slow", "integration"],
///   test_directory: "test",
///   sort_order: cli.TimeSort,
///   sort_reversed: False,
/// ))
/// ```
pub type Options {
  Options(
    seed: Option(Int),
    ignored_tags: List(String),
    test_directory: String,
    sort_order: cli.SortOrder,
    sort_reversed: Bool,
  )
}

/// Returns default options with no seed and no ignored tags.
pub fn default_options() -> Options {
  Options(
    seed: None,
    ignored_tags: [],
    test_directory: "test",
    sort_order: cli.NativeSort,
    sort_reversed: False,
  )
}

/// Run tests with the given options.
///
/// Discovers all test files in the test directory, applies CLI arguments for
/// filtering, shuffles tests using the selected seed, executes them, and
/// prints results.
///
/// ## CLI Arguments
///
/// Pass arguments after `--` when running `gleam test`:
///
/// - `--seed <int>`: Use specific seed for reproducible ordering
/// - `--module <name>`: Run only tests in matching module
/// - `--test <module.fn>`: Run a single test function
/// - `--tag <name>`: Run only tests with this tag
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
  use <- bool.guard(!condition, skip())
  next()
}

@external(erlang, "unitest_ffi", "skip")
@external(javascript, "./unitest_ffi.mjs", "skip")
fn skip() -> a

fn run_with_args(args: List(String), options: Options) -> Nil {
  case cli.parse(args) {
    Error(help) -> {
      io.println(help)
    }
    Ok(cli_opts) -> {
      let use_color = should_use_color(cli_opts.no_color)

      let tests = discover.discover_from_fs(options.test_directory)

      let chosen_seed =
        option.or(cli_opts.seed, options.seed) |> option.lazy_unwrap(auto_seed)

      let sorted =
        list.sort(tests, fn(a, b) {
          case string.compare(a.module, b.module) {
            order.Eq -> string.compare(a.name, b.name)
            other -> other
          }
        })
      let shuffled = runner.shuffle(sorted, chosen_seed)

      let plan = runner.plan(shuffled, cli_opts, options.ignored_tags)

      let sort_order = option.unwrap(cli_opts.sort_order, options.sort_order)
      let sort_reversed =
        bool.exclusive_or(cli_opts.sort_reversed, options.sort_reversed)

      execute_and_finish(
        plan,
        chosen_seed,
        use_color,
        cli_opts.reporter,
        sort_order,
        sort_reversed,
      )
    }
  }
}

fn execute_and_finish(
  plan: List(runner.PlanItem),
  seed: Int,
  use_color: Bool,
  reporter: Reporter,
  sort_order: SortOrder,
  sort_reversed: Bool,
) -> Nil {
  let package_name = get_package_name()
  let platform =
    runner.Platform(
      now_ms: now_ms_ffi,
      run_test: fn(t, k) { run_test_ffi(t, package_name, k) },
      print: io.print,
    )

  let #(on_result, cleanup) =
    build_on_result_callback(reporter, use_color, sort_order, sort_reversed)

  let on_complete = fn(exec_result: runner.ExecuteResult) {
    cleanup(exec_result)
    io.println(runner.render_summary(exec_result.report, use_color))
    halt(exit_code(exec_result.report))
  }

  runner.execute(plan, seed, platform, on_result, on_complete)
}

type OnResultCallback =
  fn(TestResult, Progress, fn() -> Nil) -> Nil

type CleanupCallback =
  fn(runner.ExecuteResult) -> Nil

fn build_on_result_callback(
  reporter: Reporter,
  use_color: Bool,
  sort_order: SortOrder,
  sort_reversed: Bool,
) -> #(OnResultCallback, CleanupCallback) {
  case reporter {
    DotReporter -> {
      let on_result = fn(result: TestResult, _progress: Progress, continue) {
        io.print(runner.outcome_char(result.outcome, use_color))
        continue()
      }
      let cleanup = fn(_: runner.ExecuteResult) { Nil }
      #(on_result, cleanup)
    }
    TableReporter -> {
      let sp =
        spinner.new("Running tests...")
        |> spinner.with_colour(ansi.cyan)
        |> spinner.start

      let on_result = fn(_result: TestResult, progress: Progress, continue) {
        let text =
          "Running tests... "
          <> int.to_string(progress.current)
          <> "/"
          <> int.to_string(progress.total)
        spinner.set_text(sp, text)

        case progress.current % yield_every_n_tests == 0 {
          True -> yield_then_ffi(continue)
          False -> continue()
        }
      }

      let cleanup = fn(exec_result: runner.ExecuteResult) {
        spinner.stop(sp)
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
pub fn exit_code(report: Report) -> Int {
  case report.failed > 0 {
    True -> 1
    False -> 0
  }
}

fn should_use_color(cli_no_color: Bool) -> Bool {
  case cli_no_color, envoy.get("NO_COLOR") {
    True, _ -> False
    _, Ok(_) -> False
    _, Error(_) -> True
  }
}

@external(erlang, "unitest_ffi", "now_ms")
@external(javascript, "./unitest_ffi.mjs", "nowMs")
fn now_ms_ffi() -> Int

@external(erlang, "unitest_ffi", "run_test_async")
@external(javascript, "./unitest_ffi.mjs", "runTestAsync")
fn run_test_ffi(
  t: Test,
  package_name: String,
  k: fn(runner.TestRunResult) -> Nil,
) -> Nil

@target(erlang)
fn yield_then_ffi(next: fn() -> Nil) -> Nil {
  next()
}

@target(javascript)
@external(javascript, "./unitest_ffi.mjs", "yieldThen")
fn yield_then_ffi(next: fn() -> Nil) -> Nil

@external(erlang, "erlang", "halt")
@external(javascript, "./unitest_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

@external(erlang, "unitest_ffi", "auto_seed")
@external(javascript, "./unitest_ffi.mjs", "autoSeed")
fn auto_seed() -> Int

fn get_package_name() -> String {
  let name_result = {
    use content <- result.try(
      simplifile.read("gleam.toml")
      |> result.replace_error("Error: Could not read gleam.toml"),
    )
    parse_package_name(content)
    |> result.replace_error("Error: Could not find 'name' in gleam.toml")
  }

  case name_result {
    Ok(name) -> name
    Error(error) -> {
      io.println_error("Error: " <> error)
      halt(1)
      ""
    }
  }
}

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
