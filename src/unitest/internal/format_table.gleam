import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleam_community/ansi
import tobble
import unitest/internal/cli
import unitest/internal/runner

pub fn render_table(
  results: List(runner.TestResult),
  use_color: Bool,
  sort_order: cli.SortOrder,
  sort_reversed: Bool,
) -> String {
  let sorted_results = sort_results(results, sort_order, sort_reversed)

  let builder =
    tobble.builder()
    |> tobble.add_row([
      header("Status", use_color),
      header("Module", use_color),
      header("Test", use_color),
      header("Duration", use_color),
    ])

  let builder =
    list.fold(sorted_results, builder, fn(b, result) {
      let runner.TestResult(item: t, outcome:, duration_ms:) = result
      let status = format_status(outcome, use_color)
      let duration = format_duration(outcome, duration_ms)
      tobble.add_row(b, [status, t.module, t.name, duration])
    })

  case tobble.build(builder) {
    Ok(table) -> tobble.render(table)
    Error(_) -> "Error: Failed to render results table."
  }
}

fn header(text: String, use_color: Bool) -> String {
  case use_color {
    True -> ansi.bold(text)
    False -> text
  }
}

fn format_status(outcome: runner.Outcome, use_color: Bool) -> String {
  case outcome, use_color {
    runner.Passed, True -> ansi.green("✓")
    runner.Passed, False -> "PASS"
    runner.Failed(_), True -> ansi.red("✗")
    runner.Failed(_), False -> "FAIL"
    runner.Skipped, True -> ansi.yellow("S")
    runner.Skipped, False -> "SKIP"
  }
}

fn format_duration(outcome: runner.Outcome, duration_ms: Int) -> String {
  case outcome {
    runner.Skipped -> "-"
    runner.Passed | runner.Failed(_) -> int.to_string(duration_ms) <> "ms"
  }
}

fn sort_results(
  results: List(runner.TestResult),
  sort_order: cli.SortOrder,
  sort_reversed: Bool,
) -> List(runner.TestResult) {
  case sort_order, sort_reversed {
    cli.NativeSort, False -> results
    cli.NativeSort, True -> list.reverse(results)
    cli.TimeSort, reversed ->
      list.sort(results, fn(a, b) { compare_by_time(a, b, reversed) })
    cli.NameSort, False ->
      list.sort(results, fn(a, b) { compare_by_name(a, b) })
    cli.NameSort, True -> list.sort(results, fn(a, b) { compare_by_name(b, a) })
  }
}

fn compare_by_name(a: runner.TestResult, b: runner.TestResult) -> order.Order {
  string.compare(a.item.module, b.item.module)
  |> order.lazy_break_tie(fn() { string.compare(a.item.name, b.item.name) })
}

fn compare_by_time(
  a: runner.TestResult,
  b: runner.TestResult,
  reversed: Bool,
) -> order.Order {
  case a.outcome, b.outcome {
    runner.Skipped, runner.Skipped -> order.Eq
    runner.Skipped, runner.Passed | runner.Skipped, runner.Failed(_) -> order.Gt
    runner.Passed, runner.Skipped | runner.Failed(_), runner.Skipped -> order.Lt
    runner.Passed, runner.Passed
    | runner.Passed, runner.Failed(_)
    | runner.Failed(_), runner.Passed
    | runner.Failed(_), runner.Failed(_)
    ->
      case reversed {
        False -> int.compare(b.duration_ms, a.duration_ms)
        True -> int.compare(a.duration_ms, b.duration_ms)
      }
  }
}
