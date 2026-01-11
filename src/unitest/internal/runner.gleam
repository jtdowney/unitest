import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleam/time/duration
import gleam_community/ansi
import prng/random
import unitest/internal/cli.{
  type CliOptions, type Filter, All, OnlyModule, OnlyTag, OnlyTest,
}
import unitest/internal/discover.{type Test}

pub type PlanItem {
  Run(Test)
  Skip(Test)
}

pub type Outcome {
  Passed
  Failed(reason: String)
  Skipped
}

pub type FailedTest {
  FailedTest(item: Test, reason: String, duration_ms: Int)
}

pub type Report {
  Report(
    passed: Int,
    failed: Int,
    skipped: Int,
    failures: List(FailedTest),
    seed: Int,
    runtime_ms: Int,
  )
}

pub type Platform {
  Platform(
    now_ms: fn() -> Int,
    run_test: fn(Test) -> Result(Nil, String),
    print: fn(String) -> Nil,
  )
}

pub fn plan(
  tests: List(Test),
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

fn should_include(t: Test, filter: Filter) -> Bool {
  case filter {
    All -> True
    OnlyTest(module, name) -> t.module == module && t.name == name
    OnlyModule(module) -> t.module == module
    OnlyTag(tag) -> list.contains(t.tags, tag)
  }
}

fn to_plan_item(t: Test, filter: Filter, ignored_tags: List(String)) -> PlanItem {
  let skip = case filter {
    OnlyTag(_) -> False
    _ -> list.any(t.tags, fn(tag) { list.contains(ignored_tags, tag) })
  }

  case skip {
    True -> Skip(t)
    False -> Run(t)
  }
}

// --- Shuffle (from rng.gleam) ---

pub fn shuffle(items: List(a), seed_value: Int) -> List(a) {
  let seed = random.new_seed(seed_value)
  let #(random_list, _) =
    random.fixed_size_list(random.float(0.0, 1.0), list.length(items))
    |> random.step(seed)
  list.zip(random_list, items)
  |> list.index_map(fn(item, idx) { #(item, idx) })
  |> list.sort(fn(a, b) {
    let #(#(key_a, _), idx_a) = a
    let #(#(key_b, _), idx_b) = b
    case float.compare(key_a, key_b) {
      order.Eq -> int.compare(idx_a, idx_b)
      other -> other
    }
  })
  |> list.map(fn(tuple) {
    let #(#(_, item), _) = tuple
    item
  })
}

pub fn execute(
  plan: List(PlanItem),
  seed: Int,
  platform: Platform,
  use_color: Bool,
) -> Report {
  let start_ms = platform.now_ms()

  let #(passed, failed, skipped, failures) =
    list.fold(plan, #(0, 0, 0, []), fn(acc, item) {
      let #(p, f, s, fails) = acc
      case item {
        Run(t) -> {
          let test_start = platform.now_ms()
          case platform.run_test(t) {
            Ok(Nil) -> {
              platform.print(outcome_char(Passed, use_color))
              #(p + 1, f, s, fails)
            }
            Error(reason) -> {
              let test_end = platform.now_ms()
              let duration = test_end - test_start
              platform.print(outcome_char(Failed(reason), use_color))
              let failure =
                FailedTest(item: t, reason: reason, duration_ms: duration)
              #(p, f + 1, s, list.append(fails, [failure]))
            }
          }
        }
        Skip(_t) -> {
          platform.print(outcome_char(Skipped, use_color))
          #(p, f, s + 1, fails)
        }
      }
    })

  let end_ms = platform.now_ms()

  Report(
    passed: passed,
    failed: failed,
    skipped: skipped,
    failures: failures,
    seed: seed,
    runtime_ms: end_ms - start_ms,
  )
}

pub fn outcome_char(outcome: Outcome, use_color: Bool) -> String {
  case outcome, use_color {
    Passed, True -> ansi.green(".")
    Passed, False -> "."
    Failed(_), True -> ansi.red("F")
    Failed(_), False -> "F"
    Skipped, True -> ansi.yellow("S")
    Skipped, False -> "S"
  }
}

pub fn render_summary(report: Report, use_color: Bool) -> String {
  let status_line = format_status(report.passed, report.failed, use_color)
  let skipped_line = format_skipped(report.skipped, use_color)
  let seed_line = "Seed: " <> int.to_string(report.seed)
  let time_line = "Finished in " <> format_duration(report.runtime_ms)

  let failure_details = case report.failures {
    [] -> ""
    failures -> "\n\nFailures:\n" <> render_failures(failures, use_color)
  }

  string.join(
    ["\n", status_line <> skipped_line, time_line, seed_line, failure_details],
    "\n",
  )
}

fn format_status(passed: Int, failed: Int, use_color: Bool) -> String {
  let text = case failed {
    0 -> int.to_string(passed) <> " passed, no failures"
    _ ->
      int.to_string(passed)
      <> " passed, "
      <> int.to_string(failed)
      <> " failures"
  }

  case use_color, failed {
    True, 0 -> ansi.green(text)
    True, _ -> ansi.red(text)
    False, _ -> text
  }
}

fn format_skipped(skipped: Int, use_color: Bool) -> String {
  case skipped {
    0 -> ""
    n -> {
      let text = ", " <> int.to_string(n) <> " skipped"
      case use_color {
        True -> ansi.yellow(text)
        False -> text
      }
    }
  }
}

fn render_failures(failures: List(FailedTest), use_color: Bool) -> String {
  failures
  |> list.index_map(fn(f, idx) {
    let num = int.to_string(idx + 1)
    let name = f.item.module <> "." <> f.item.name
    let dur = " (" <> format_duration(f.duration_ms) <> ")"
    let header = num <> ") " <> name <> dur
    let header = case use_color {
      True -> ansi.red(header)
      False -> header
    }
    header <> "\n   " <> f.reason
  })
  |> string.join("\n\n")
}

fn format_duration(ms: Int) -> String {
  let #(amount, unit) = duration.milliseconds(ms) |> duration.approximate
  int.to_string(amount) <> " " <> unit_to_string(amount, unit)
}

fn unit_to_string(amount: Int, unit: duration.Unit) -> String {
  let plural = amount != 1
  case unit, plural {
    duration.Nanosecond, False -> "nanosecond"
    duration.Nanosecond, True -> "nanoseconds"
    duration.Microsecond, False -> "microsecond"
    duration.Microsecond, True -> "microseconds"
    duration.Millisecond, False -> "millisecond"
    duration.Millisecond, True -> "milliseconds"
    duration.Second, False -> "second"
    duration.Second, True -> "seconds"
    duration.Minute, False -> "minute"
    duration.Minute, True -> "minutes"
    duration.Hour, False -> "hour"
    duration.Hour, True -> "hours"
    duration.Day, False -> "day"
    duration.Day, True -> "days"
    duration.Week, False -> "week"
    duration.Week, True -> "weeks"
    duration.Month, False -> "month"
    duration.Month, True -> "months"
    duration.Year, False -> "year"
    duration.Year, True -> "years"
  }
}
