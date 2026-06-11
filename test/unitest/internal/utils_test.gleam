import birdie
import gleam/int
import gleam/list
import gleam/string
import gleam/time/duration
import unitest/internal/utils

pub fn format_duration_edge_cases_test() {
  [
    0, 1, 500, 999, 1000, 1050, 1500, 45_000, 59_999, 60_000, 90_000, 300_000,
    3_599_000, 3_600_000, 3_723_000, 90_000_000,
  ]
  |> list.map(fn(ms) {
    int.to_string(ms)
    <> " ms -> "
    <> utils.format_duration(duration.milliseconds(ms))
  })
  |> string.join("\n")
  |> birdie.snap("format_duration across edge cases")
}

pub fn join_present_skips_empty_parts_test() {
  assert utils.join_present(["a", "", "b"], ", ") == "a, b"
  assert utils.join_present(["", ""], ", ") == ""
}

pub fn maybe_color_applies_only_when_enabled_test() {
  let bracket = fn(text) { "<" <> text <> ">" }
  assert utils.maybe_color("x", True, bracket) == "<x>"
  assert utils.maybe_color("x", False, bracket) == "x"
}
