import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string
import gleam/time/duration
import gleam_community/ansi
import prng/random
import unitest/internal/cli.{
  type CliOptions, type Filter, AllLocations, OnlyFile, OnlyFileAtLine, OnlyTest,
}
import unitest/internal/discover.{type LineSpan, type Test}
import unitest/internal/test_failure.{type TestFailure, Assert, LetAssert}

pub type PlanItem {
  Run(Test)
  Skip(Test)
}

pub type Outcome {
  Passed
  Failed(reason: TestFailure)
  Skipped
}

pub type FailedTest {
  FailedTest(item: Test, error: TestFailure, duration_ms: Int)
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
    run_test: fn(Test) -> Result(Nil, TestFailure),
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
  test_path == filter_path || string.ends_with(test_path, "/" <> filter_path)
}

fn line_in_span(line: Int, span: LineSpan) -> Bool {
  line >= span.start_line && line <= span.end_line
}

fn to_plan_item(t: Test, filter: Filter, ignored_tags: List(String)) -> PlanItem {
  // Skip ignored_tags check when explicitly targeting:
  // - A specific tag (--tag)
  // - A specific test (--test)
  // - A specific line (file:line)
  let skip = case filter.tag, filter.location {
    option.Some(_), _ -> False
    _, OnlyTest(_, _) -> False
    _, OnlyFileAtLine(_, _) -> False
    _, _ -> list.any(t.tags, fn(tag) { list.contains(ignored_tags, tag) })
  }

  case skip {
    True -> Skip(t)
    False -> Run(t)
  }
}

pub fn shuffle(items: List(a), seed_value: Int) -> List(a) {
  let seed = random.new_seed(seed_value)
  let #(keys, _) =
    random.fixed_size_list(random.float(0.0, 1.0), list.length(items))
    |> random.step(seed)

  list.zip(keys, items)
  |> list.index_map(fn(pair, idx) {
    let #(key, item) = pair
    #(key, idx, item)
  })
  |> list.sort(fn(a, b) {
    let #(key_a, idx_a, _) = a
    let #(key_b, idx_b, _) = b
    case float.compare(key_a, key_b) {
      order.Eq -> int.compare(idx_a, idx_b)
      other -> other
    }
  })
  |> list.map(fn(triple) { triple.2 })
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
            Error(err) -> {
              let test_end = platform.now_ms()
              let duration = test_end - test_start
              platform.print(outcome_char(Failed(err), use_color))
              let failure =
                FailedTest(item: t, error: err, duration_ms: duration)
              #(p, f + 1, s, [failure, ..fails])
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
    failures: list.reverse(failures),
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
    let source = case f.error.kind {
      Assert(start:, end:, ..) ->
        test_failure.extract_snippet(f.error.file, start, end)
      LetAssert(start:, end:, ..) ->
        test_failure.extract_snippet(f.error.file, start, end)
      _ -> option.None
    }

    test_failure.format_failure(
      idx + 1,
      f.item.module,
      f.item.name,
      f.duration_ms,
      f.error,
      source,
      use_color,
    )
  })
  |> string.join("\n\n")
}

fn format_duration(ms: Int) -> String {
  let #(amount, unit) = duration.milliseconds(ms) |> duration.approximate
  int.to_string(amount) <> " " <> unit_to_string(amount, unit)
}

fn unit_to_string(amount: Int, unit: duration.Unit) -> String {
  let base = case unit {
    duration.Nanosecond -> "nanosecond"
    duration.Microsecond -> "microsecond"
    duration.Millisecond -> "millisecond"
    duration.Second -> "second"
    duration.Minute -> "minute"
    duration.Hour -> "hour"
    duration.Day -> "day"
    duration.Week -> "week"
    duration.Month -> "month"
    duration.Year -> "year"
  }
  case amount == 1 {
    True -> base
    False -> base <> "s"
  }
}
