import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import gleam/time/duration
import gleam_community/ansi
import unitest/internal/cli.{
  type CliOptions, type Filter, AllLocations, OnlyFile, OnlyFileAtLine, OnlyTest,
}
import unitest/internal/discover.{type LineSpan, type Test}
import unitest/internal/test_failure.{type TestFailure, Assert, LetAssert}

pub type TestRunResult {
  Ran
  RuntimeSkip
  RunError(TestFailure)
}

pub type PlanItem {
  Run(Test)
  Skip(Test)
}

pub type Outcome {
  Passed
  Failed(reason: TestFailure)
  Skipped
}

pub type TestResult {
  TestResult(item: Test, outcome: Outcome, duration_ms: Int)
}

pub type Report {
  Report(
    passed: Int,
    failed: Int,
    skipped: Int,
    failures: List(TestResult),
    seed: Int,
    runtime_ms: Int,
  )
}

pub type Platform {
  Platform(
    now_ms: fn() -> Int,
    run_test: fn(Test, fn(TestRunResult) -> Nil) -> Nil,
    print: fn(String) -> Nil,
  )
}

type ExecutionState {
  ExecutionState(
    passed: Int,
    failed: Int,
    skipped: Int,
    failures: List(TestResult),
    results: List(TestResult),
    idx: Int,
  )
}

type ExecutionContext {
  ExecutionContext(
    seed: Int,
    platform: Platform,
    on_result: fn(TestResult, Progress, fn() -> Nil) -> Nil,
    on_complete: fn(ExecuteResult) -> Nil,
    start_ms: Int,
    total: Int,
  )
}

fn initial_state() -> ExecutionState {
  ExecutionState(
    passed: 0,
    failed: 0,
    skipped: 0,
    failures: [],
    results: [],
    idx: 0,
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
  let has_ignored_tag =
    list.any(t.tags, fn(tag) { list.contains(ignored_tags, tag) })

  let should_skip = case filter.tag, filter.location {
    option.Some(_), _ -> False
    _, OnlyTest(_, _) -> False
    _, OnlyFileAtLine(_, _) -> False
    _, _ -> has_ignored_tag
  }

  case should_skip {
    True -> Skip(t)
    False -> Run(t)
  }
}

pub type Progress {
  Progress(current: Int, total: Int)
}

pub type ExecuteResult {
  ExecuteResult(report: Report, results: List(TestResult))
}

pub fn execute(
  plan: List(PlanItem),
  seed: Int,
  platform: Platform,
  on_result: fn(TestResult, Progress, fn() -> Nil) -> Nil,
  on_complete: fn(ExecuteResult) -> Nil,
) -> Nil {
  let ctx =
    ExecutionContext(
      seed:,
      platform:,
      on_result:,
      on_complete:,
      start_ms: platform.now_ms(),
      total: list.length(plan),
    )
  execute_loop(plan, ctx, initial_state())
}

fn execute_loop(
  plan: List(PlanItem),
  ctx: ExecutionContext,
  state: ExecutionState,
) -> Nil {
  case plan {
    [] -> {
      let runtime_ms = ctx.platform.now_ms() - ctx.start_ms
      let report = build_report(state, ctx.seed, runtime_ms)
      ctx.on_complete(ExecuteResult(
        report:,
        results: list.reverse(state.results),
      ))
    }
    [Run(t), ..rest] -> {
      let test_start = ctx.platform.now_ms()
      let progress = Progress(current: state.idx + 1, total: ctx.total)

      ctx.platform.run_test(t, fn(test_result) {
        let duration = ctx.platform.now_ms() - test_start
        let #(result, new_state) =
          process_run_result(t, test_result, duration, state)

        ctx.on_result(result, progress, fn() {
          execute_loop(rest, ctx, new_state)
        })
      })
    }
    [Skip(t), ..rest] -> {
      let progress = Progress(current: state.idx + 1, total: ctx.total)
      let result = TestResult(item: t, outcome: Skipped, duration_ms: 0)
      let new_state =
        ExecutionState(
          ..state,
          skipped: state.skipped + 1,
          results: [result, ..state.results],
          idx: state.idx + 1,
        )

      ctx.on_result(result, progress, fn() {
        execute_loop(rest, ctx, new_state)
      })
    }
  }
}

fn process_run_result(
  t: Test,
  result: TestRunResult,
  duration: Int,
  state: ExecutionState,
) -> #(TestResult, ExecutionState) {
  case result {
    Ran -> {
      let test_result =
        TestResult(item: t, outcome: Passed, duration_ms: duration)
      #(
        test_result,
        ExecutionState(
          ..state,
          passed: state.passed + 1,
          results: [test_result, ..state.results],
          idx: state.idx + 1,
        ),
      )
    }
    RuntimeSkip -> {
      let test_result =
        TestResult(item: t, outcome: Skipped, duration_ms: duration)
      #(
        test_result,
        ExecutionState(
          ..state,
          skipped: state.skipped + 1,
          results: [test_result, ..state.results],
          idx: state.idx + 1,
        ),
      )
    }
    RunError(err) -> {
      let test_result =
        TestResult(item: t, outcome: Failed(err), duration_ms: duration)
      #(
        test_result,
        ExecutionState(
          ..state,
          failed: state.failed + 1,
          failures: [test_result, ..state.failures],
          results: [test_result, ..state.results],
          idx: state.idx + 1,
        ),
      )
    }
  }
}

fn build_report(state: ExecutionState, seed: Int, runtime_ms: Int) -> Report {
  Report(
    passed: state.passed,
    failed: state.failed,
    skipped: state.skipped,
    failures: list.reverse(state.failures),
    seed:,
    runtime_ms:,
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
  use <- bool.guard(skipped == 0, "")
  let text = ", " <> int.to_string(skipped) <> " skipped"
  case use_color {
    True -> ansi.yellow(text)
    False -> text
  }
}

fn render_failures(failures: List(TestResult), use_color: Bool) -> String {
  failures
  |> list.index_map(fn(f, idx) {
    let assert Failed(error) = f.outcome
    let source = case error.kind {
      Assert(start:, end:, ..) ->
        test_failure.extract_snippet(error.file, start, end)
      LetAssert(start:, end:, ..) ->
        test_failure.extract_snippet(error.file, start, end)
      _ -> option.None
    }

    test_failure.format_failure(
      idx + 1,
      f.item.module,
      f.item.name,
      f.duration_ms,
      error,
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
