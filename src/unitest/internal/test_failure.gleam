import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam_community/ansi
import simplifile
import unitest/internal/utils

pub type TestFailure {
  TestFailure(message: String, file: String, line: Int, kind: FailureKind)
}

pub type FailureKind {
  Assert(start: Int, end: Int, kind: AssertKind)
  Panic
  Todo
  LetAssert(start: Int, end: Int, value: String)
  Timeout(timeout_ms: Int)
  Crashed(reason: String, stack: List(StackFrame))
  Undef(module: String, function: String, arity: Int)
  Generic
}

pub type StackFrame {
  StackFrame(
    module: String,
    function: String,
    arity: Int,
    file: String,
    line: Int,
  )
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

/// Drop frames inside unitest's own runner/FFI so crash traces show user code.
pub fn drop_internal_frames(stack: List(StackFrame)) -> List(StackFrame) {
  list.filter(stack, is_user_frame)
}

fn is_user_frame(frame: StackFrame) -> Bool {
  !{
    frame.module == "unitest"
    || string.starts_with(frame.module, "unitest@")
    || frame.module == "unitest_ffi"
    || string.contains(frame.file, "/javascript/unitest/")
    || string.starts_with(frame.file, "node:")
  }
}

pub fn extract_snippet(
  file: String,
  start: Int,
  end: Int,
) -> Result(String, Nil) {
  use <- bool.guard(when: start <= 0 || end <= start, return: Error(Nil))
  let length = end - start

  use content <- result.try(
    simplifile.read_bits(file) |> result.replace_error(Nil),
  )
  use snippet_bits <- result.try(bit_array.slice(content, start, length))
  bit_array.to_string(snippet_bits)
  |> result.replace_error(Nil)
  |> result.map(string.trim)
}

pub fn format_failure(
  index index: Int,
  module module: String,
  name name: String,
  duration elapsed: duration.Duration,
  error error: TestFailure,
  source source: Option(String),
  use_color use_color: Bool,
) -> String {
  let header = format_header(index, module, name, elapsed, use_color)
  let location = format_location(error.file, error.line, use_color)

  let #(snippet, values) = case error.kind, source {
    Assert(kind: assert_kind, ..), option.Some(code) ->
      format_assertion_with_labels(code, assert_kind, use_color)
    _, _ -> #(
      format_snippet(source, use_color),
      format_values(error.kind, use_color),
    )
  }

  let message = format_message(message_text(error), use_color)

  utils.join_present([header, location, snippet, values, message], "\n")
}

fn format_header(
  index: Int,
  module: String,
  name: String,
  elapsed: duration.Duration,
  use_color: Bool,
) -> String {
  let text =
    int.to_string(index)
    <> ") "
    <> module
    <> "."
    <> name
    <> " ("
    <> utils.format_duration(elapsed)
    <> ")"
  utils.maybe_color(text, use_color, ansi.red)
}

fn format_location(file: String, line: Int, use_color: Bool) -> String {
  case file, line {
    "", _ | _, 0 -> ""
    f, l -> {
      let text = "   " <> f <> ":" <> int.to_string(l)
      utils.maybe_color(text, use_color, ansi.dim)
    }
  }
}

fn color_snippet(code: String, use_color: Bool) -> String {
  utils.maybe_color("\n     " <> code, use_color, ansi.cyan)
}

fn format_snippet(source: Option(String), use_color: Bool) -> String {
  case source {
    option.None -> ""
    option.Some(code) -> color_snippet(code, use_color)
  }
}

fn format_values(kind: FailureKind, use_color: Bool) -> String {
  case kind {
    Assert(kind: assert_kind, ..) ->
      format_assert_values(assert_kind, use_color)
    LetAssert(value: "", ..) -> ""
    LetAssert(value: v, ..) ->
      utils.maybe_color("\n   value: " <> v, use_color, ansi.yellow)
    Panic | Todo | Generic | Timeout(..) | Crashed(..) | Undef(..) -> ""
  }
}

fn message_text(failure: TestFailure) -> String {
  case failure.kind {
    Timeout(timeout_ms:) ->
      "Test timed out after " <> int.to_string(timeout_ms) <> "ms"
    Crashed(reason:, stack:) ->
      "Process crashed: " <> reason <> stack_suffix(stack)
    Undef(module:, function:, arity:) ->
      "Undefined function: "
      <> module
      <> ":"
      <> function
      <> "/"
      <> int.to_string(arity)
    Assert(..) | Panic | Todo | LetAssert(..) | Generic -> failure.message
  }
}

fn stack_suffix(stack: List(StackFrame)) -> String {
  stack
  |> drop_internal_frames
  |> list.map(frame_line)
  |> string.concat
}

fn frame_line(frame: StackFrame) -> String {
  let location = case frame.file {
    "" -> ""
    file -> " (" <> file <> ":" <> int.to_string(frame.line) <> ")"
  }
  "\n  in "
  <> frame.module
  <> ":"
  <> frame.function
  <> "/"
  <> int.to_string(frame.arity)
  <> location
}

fn format_assert_values(kind: AssertKind, use_color: Bool) -> String {
  case kind {
    BinaryOperator(operator:, left:, right:) -> {
      let left_val = format_expr_value(left.kind)
      let right_val = format_expr_value(right.kind)
      case left_val, right_val {
        "", "" -> ""
        left_value, right_value -> {
          let op_text = "   operator: " <> operator
          let left_text = "   left:  " <> left_value
          let right_text = "   right: " <> right_value
          let text = "\n" <> left_text <> "\n" <> right_text <> "\n" <> op_text
          utils.maybe_color(text, use_color, ansi.yellow)
        }
      }
    }
    FunctionCall(arguments:) -> {
      let args =
        list.index_map(arguments, fn(arg, index) {
          case format_expr_value(arg.kind) {
            "" -> ""
            v -> "   arg " <> int.to_string(index) <> ": " <> v
          }
        })
      case utils.join_present(args, "\n") {
        "" -> ""
        text -> utils.maybe_color("\n" <> text, use_color, ansi.yellow)
      }
    }
    OtherExpression(expression:) -> {
      let val = format_expr_value(expression.kind)
      case val {
        "" -> ""
        v -> utils.maybe_color("\n   value: " <> v, use_color, ansi.yellow)
      }
    }
  }
}

fn format_expr_value(kind: ExprKind) -> String {
  case kind {
    Literal(value:) | Expression(value:) -> value
    Unevaluated -> ""
  }
}

fn format_message(message: String, use_color: Bool) -> String {
  case message {
    "" -> ""
    _ -> utils.maybe_color("   " <> message, use_color, ansi.red)
  }
}

fn format_assertion_with_labels(
  code: String,
  kind: AssertKind,
  use_color: Bool,
) -> #(String, String) {
  let snippet = color_snippet(code, use_color)

  case kind {
    BinaryOperator(left:, right:, ..) -> {
      let left_val = format_expr_value(left.kind)
      let right_val = format_expr_value(right.kind)

      case left_val, right_val {
        "", "" -> #(snippet, "")
        _, _ -> {
          let values_text =
            "\n   left:  "
            <> left_val
            <> expr_kind_label(left.kind)
            <> "\n   right: "
            <> right_val
            <> expr_kind_label(right.kind)

          let values = utils.maybe_color(values_text, use_color, ansi.yellow)

          #(snippet, values)
        }
      }
    }
    FunctionCall(..) | OtherExpression(..) -> #(
      snippet,
      format_assert_values(kind, use_color),
    )
  }
}

fn expr_kind_label(kind: ExprKind) -> String {
  case kind {
    Literal(_) -> " (literal)"
    Expression(_) -> " (expression)"
    Unevaluated -> ""
  }
}
