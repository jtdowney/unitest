import gleam/int
import gleam/list
import gleam_community/ansi
import tobble
import unitest/internal/runner.{
  type TestResult, Failed, Passed, Skipped, TestResult,
}

pub fn render_table(results: List(TestResult), use_color: Bool) -> String {
  let builder =
    tobble.builder()
    |> tobble.add_row([
      header("Status", use_color),
      header("Module", use_color),
      header("Test", use_color),
      header("Duration", use_color),
    ])

  let builder =
    list.fold(results, builder, fn(b, result) {
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
