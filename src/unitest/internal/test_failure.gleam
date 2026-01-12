import gleam/bit_array
import gleam/bool.{guard}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam_community/ansi
import simplifile

pub type TestFailure {
  TestFailure(
    message: String,
    file: String,
    module: String,
    function: String,
    line: Int,
    kind: PanicKind,
  )
}

pub type PanicKind {
  Assert(start: Int, end: Int, expression_start: Int, kind: AssertKind)
  Panic
  Todo
  LetAssert(start: Int, end: Int, value: String)
  Generic
}

pub type AssertKind {
  BinaryOperator(operator: String, left: AssertedExpr, right: AssertedExpr)
  FunctionCall(arguments: List(AssertedExpr))
  OtherExpression(expression: AssertedExpr)
}

pub type AssertedExpr {
  AssertedExpr(start: Int, end: Int, kind: ExprKind)
}

pub type ExprKind {
  Literal(value: String)
  Expression(value: String)
  Unevaluated
}

fn maybe_color(
  text: String,
  use_color: Bool,
  color_fn: fn(String) -> String,
) -> String {
  case use_color {
    True -> color_fn(text)
    False -> text
  }
}

pub fn format_failure(
  index: Int,
  test_module: String,
  test_name: String,
  duration_ms: Int,
  error: TestFailure,
  source: Option(String),
  use_color: Bool,
) -> String {
  let header =
    format_header(index, test_module, test_name, duration_ms, use_color)
  let location = format_location(error.file, error.line, use_color)

  let #(snippet, values) = case error.kind, source {
    Assert(kind: assert_kind, ..), Some(code) ->
      format_assertion_with_labels(code, assert_kind, use_color)
    _, _ -> #(
      format_snippet(source, use_color),
      format_values(error.kind, use_color),
    )
  }

  let message = format_message(error.message, use_color)

  string.join(
    [header, location, snippet, values, message]
      |> list.filter(fn(s) { s != "" }),
    "\n",
  )
}

fn format_header(
  index: Int,
  module: String,
  name: String,
  duration_ms: Int,
  use_color: Bool,
) -> String {
  let num = int.to_string(index)
  let test_name = module <> "." <> name
  let dur = " (" <> format_duration(duration_ms) <> ")"
  let text = num <> ") " <> test_name <> dur
  maybe_color(text, use_color, ansi.red)
}

fn format_location(file: String, line: Int, use_color: Bool) -> String {
  case file, line {
    "", _ | _, 0 -> ""
    f, l -> {
      let text = "   " <> f <> ":" <> int.to_string(l)
      maybe_color(text, use_color, ansi.dim)
    }
  }
}

fn format_snippet(source: Option(String), use_color: Bool) -> String {
  case source {
    None -> ""
    Some(code) -> {
      let text = "\n     " <> code
      maybe_color(text, use_color, ansi.cyan)
    }
  }
}

fn format_values(kind: PanicKind, use_color: Bool) -> String {
  case kind {
    Assert(kind: assert_kind, ..) ->
      format_assert_values(assert_kind, use_color)
    LetAssert(value: "", ..) -> ""
    LetAssert(value: v, ..) -> {
      let text = "\n   value: " <> v
      maybe_color(text, use_color, ansi.yellow)
    }
    Panic | Todo | Generic -> ""
  }
}

fn format_assert_values(kind: AssertKind, use_color: Bool) -> String {
  case kind {
    BinaryOperator(operator:, left:, right:) -> {
      let left_val = format_expr_value(left.kind)
      let right_val = format_expr_value(right.kind)
      case left_val, right_val {
        "", "" -> ""
        l, r -> {
          let op_text = "   operator: " <> operator
          let left_text = "   left:  " <> l
          let right_text = "   right: " <> r
          let text = "\n" <> left_text <> "\n" <> right_text <> "\n" <> op_text
          maybe_color(text, use_color, ansi.yellow)
        }
      }
    }
    FunctionCall(arguments:) -> {
      let args =
        arguments
        |> list.index_map(fn(arg, idx) {
          let val = format_expr_value(arg.kind)
          case val {
            "" -> ""
            v -> "   arg " <> int.to_string(idx) <> ": " <> v
          }
        })
        |> list.filter(fn(s) { s != "" })
      case args {
        [] -> ""
        _ -> {
          let text = "\n" <> string.join(args, "\n")
          maybe_color(text, use_color, ansi.yellow)
        }
      }
    }
    OtherExpression(expression:) -> {
      let val = format_expr_value(expression.kind)
      case val {
        "" -> ""
        v -> {
          let text = "\n   value: " <> v
          maybe_color(text, use_color, ansi.yellow)
        }
      }
    }
  }
}

fn format_expr_value(kind: ExprKind) -> String {
  case kind {
    Literal(value:) -> value
    Expression(value:) -> value
    Unevaluated -> ""
  }
}

fn format_message(message: String, use_color: Bool) -> String {
  let text = "   " <> message
  maybe_color(text, use_color, ansi.red)
}

fn format_duration(ms: Int) -> String {
  case ms {
    0 -> "< 1 ms"
    1 -> "1 ms"
    n if n < 1000 -> int.to_string(n) <> " ms"
    n -> {
      let secs = n / 1000
      let remainder = n % 1000
      case remainder {
        0 -> int.to_string(secs) <> " s"
        _ -> int.to_string(secs) <> "." <> pad_left(remainder, 3) <> " s"
      }
    }
  }
}

fn pad_left(n: Int, width: Int) -> String {
  let s = int.to_string(n)
  let padding = width - string.length(s)
  case padding > 0 {
    True -> string.repeat("0", padding) <> s
    False -> s
  }
}

fn format_assertion_with_labels(
  code: String,
  kind: AssertKind,
  use_color: Bool,
) -> #(String, String) {
  let snippet = maybe_color("\n     " <> code, use_color, ansi.cyan)

  case kind {
    BinaryOperator(left:, right:, ..) -> {
      let left_val = format_expr_value(left.kind)
      let right_val = format_expr_value(right.kind)

      let values_text =
        "\n   left:  "
        <> left_val
        <> expr_kind_label(left.kind)
        <> "\n   right: "
        <> right_val
        <> expr_kind_label(right.kind)

      let values = maybe_color(values_text, use_color, ansi.yellow)

      #(snippet, values)
    }
    _ -> #(snippet, format_values(Assert(0, 0, 0, kind), use_color))
  }
}

fn expr_kind_label(kind: ExprKind) -> String {
  case kind {
    Literal(_) -> " (literal)"
    Expression(_) -> " (expression)"
    Unevaluated -> ""
  }
}

pub fn extract_snippet(file: String, start: Int, end: Int) -> Option(String) {
  use <- guard(start <= 0 || end <= start, None)
  let length = end - start

  let result = {
    use content <- result.try(
      simplifile.read_bits(file) |> result.replace_error(Nil),
    )
    use snippet_bits <- result.try(slice_bits(content, start, length))
    bit_array.to_string(snippet_bits) |> result.replace_error(Nil)
  }

  result
  |> result.map(string.trim)
  |> option.from_result
}

fn slice_bits(bits: BitArray, start: Int, length: Int) -> Result(BitArray, Nil) {
  let total = bit_array.byte_size(bits)
  case start >= 0 && start + length <= total {
    False -> Error(Nil)
    True -> Ok(bit_array.slice(bits, start, length) |> result.unwrap(<<>>))
  }
}
