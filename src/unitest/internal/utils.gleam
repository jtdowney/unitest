import gleam/int
import gleam/list
import gleam/string
import gleam/time/duration

pub fn format_duration(elapsed: duration.Duration) -> String {
  case duration.to_milliseconds(elapsed) {
    0 -> "< 1ms"
    n if n < 1000 -> int.to_string(n) <> "ms"
    n if n < 60_000 -> format_seconds(n)
    n if n < 3_600_000 -> format_minutes(n)
    n -> format_hours(n)
  }
}

fn format_seconds(ms: Int) -> String {
  let seconds = ms / 1000
  let tenths = ms % 1000 / 100
  case tenths {
    0 -> int.to_string(seconds) <> "s"
    _ -> int.to_string(seconds) <> "." <> int.to_string(tenths) <> "s"
  }
}

fn format_minutes(ms: Int) -> String {
  let total_seconds = ms / 1000
  let minutes = total_seconds / 60
  let seconds = total_seconds % 60
  int.to_string(minutes) <> "m " <> int.to_string(seconds) <> "s"
}

fn format_hours(ms: Int) -> String {
  let total_minutes = ms / 60_000
  let hours = total_minutes / 60
  let minutes = total_minutes % 60
  int.to_string(hours) <> "h " <> int.to_string(minutes) <> "m"
}

pub fn join_present(parts: List(String), separator: String) -> String {
  parts
  |> list.filter(fn(part) { part != "" })
  |> string.join(separator)
}

pub fn maybe_color(
  text: String,
  use_color: Bool,
  color: fn(String) -> String,
) -> String {
  case use_color {
    True -> color(text)
    False -> text
  }
}
