import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleam_community/ansi
import tobble
import unitest/internal/cli.{type SortOrder, NameSort, NativeSort, TimeSort}
import unitest/internal/runner.{
  type TestResult, Failed, Passed, Skipped, TestResult,
}

pub fn render_table(
  results: List(TestResult),
  use_color: Bool,
  sort_order: SortOrder,
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
      let TestResult(item: t, outcome:, duration_ms:) = result
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
    Passed, True -> ansi.green("✓")
    Passed, False -> "PASS"
    Failed(_), True -> ansi.red("✗")
    Failed(_), False -> "FAIL"
    Skipped, True -> ansi.yellow("S")
    Skipped, False -> "SKIP"
  }
}

fn format_duration(outcome: runner.Outcome, duration_ms: Int) -> String {
  case outcome {
    Skipped -> "-"
    _ -> int.to_string(duration_ms) <> "ms"
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
    NameSort, False -> list.sort(results, fn(a, b) { compare_by_name(a, b) })
    NameSort, True -> list.sort(results, fn(a, b) { compare_by_name(b, a) })
  }
}

fn compare_by_name(a: TestResult, b: TestResult) -> order.Order {
  string.compare(a.item.module, b.item.module)
  |> order.lazy_break_tie(fn() { string.compare(a.item.name, b.item.name) })
}

fn compare_by_time(a: TestResult, b: TestResult, reversed: Bool) -> order.Order {
  case a.outcome, b.outcome {
    // Both skipped - equal
    Skipped, Skipped -> order.Eq
    // Skipped always comes last
    Skipped, _ -> order.Gt
    _, Skipped -> order.Lt
    _, _ ->
      case reversed {
        False -> int.compare(b.duration_ms, a.duration_ms)
        True -> int.compare(a.duration_ms, b.duration_ms)
      }
  }
}
