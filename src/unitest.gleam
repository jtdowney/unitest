//// Unitest is a Gleam test runner with random ordering, tagging, and CLI filtering.
////
//// Drop-in replacement for gleeunit with additional features:
//// - Random test ordering with reproducible seeds
//// - Test tagging for selective execution
//// - CLI filtering by module, test, or tag

import argv
import envoy
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam/string
import unitest/internal/cli
import unitest/internal/discover.{type Test}
import unitest/internal/runner.{type Report}
import unitest/internal/test_failure.{type TestFailure}

/// Configuration options for the test runner.
///
/// ## Fields
///
/// - `seed`: Optional seed for deterministic test ordering. When `None`,
///   a random seed is generated automatically.
/// - `ignored_tags`: Tests with any of these tags will be skipped and
///   reported as `S` in the output.
/// - `test_directory`: Directory containing test files.
///
/// ## Example
///
/// ```gleam
/// unitest.run(Options(
///   seed: Some(12345),
///   ignored_tags: ["slow", "integration"],
///   test_directory: "test",
/// ))
/// ```
pub type Options {
  Options(seed: Option(Int), ignored_tags: List(String), test_directory: String)
}

/// Returns default options with no seed and no ignored tags.
pub fn default_options() -> Options {
  Options(seed: None, ignored_tags: [], test_directory: "test")
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

      execute_and_finish(plan, chosen_seed, use_color)
    }
  }
}

@external(javascript, "./unitest_ffi.mjs", "execute_and_finish_js")
fn execute_and_finish(
  plan: List(runner.PlanItem),
  seed: Int,
  use_color: Bool,
) -> Nil {
  let platform =
    runner.Platform(now_ms: now_ms_ffi, run_test: run_test_ffi, print: io.print)
  let report = runner.execute(plan, seed, platform, use_color)
  let summary = runner.render_summary(report, use_color)

  io.println(summary)

  report
  |> exit_code
  |> halt
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
fn now_ms_ffi() -> Int

@external(erlang, "unitest_ffi", "run_test")
fn run_test_ffi(t: Test) -> Result(Nil, TestFailure)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

@external(erlang, "unitest_ffi", "auto_seed")
@external(javascript, "./unitest_ffi.mjs", "autoSeed")
fn auto_seed() -> Int
