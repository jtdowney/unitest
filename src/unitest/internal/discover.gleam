import glance
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type LineSpan {
  LineSpan(start_line: Int, end_line: Int)
}

pub type Test {
  Test(
    module: String,
    name: String,
    tags: List(String),
    file_path: String,
    line_span: LineSpan,
  )
}

pub type ParsedTest {
  ParsedTest(name: String, tags: List(String), byte_span: glance.Span)
}

pub fn path_to_module(path: String, base_path: String) -> String {
  let prefix_length = string.length(base_path) + 1
  path
  |> string.drop_start(prefix_length)
  |> string.drop_end(6)
}

pub fn byte_offset_to_line(source: String, byte_offset: Int) -> Int {
  let bytes = bit_array.from_string(source)
  count_newlines_in_bytes(bytes, byte_offset, 0) + 1
}

fn count_newlines_in_bytes(bytes: BitArray, remaining: Int, count: Int) -> Int {
  case remaining <= 0 {
    True -> count
    False ->
      case bytes {
        <<0x0A, rest:bits>> ->
          count_newlines_in_bytes(rest, remaining - 1, count + 1)
        <<_byte, rest:bits>> ->
          count_newlines_in_bytes(rest, remaining - 1, count)
        _ -> count
      }
  }
}

pub fn discover_from_fs(base_path: String) -> List(Test) {
  simplifile.get_files(base_path)
  |> result.unwrap([])
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.flat_map(fn(path) { discover_tests_in_file(path, base_path) })
}

fn discover_tests_in_file(path: String, base_path: String) -> List(Test) {
  let module_name = path_to_module(path, base_path)

  case simplifile.read(path) {
    Error(_) -> []
    Ok(contents) ->
      parse_module(contents)
      |> result.unwrap([])
      |> list.map(fn(pt) {
        let start_line = byte_offset_to_line(contents, pt.byte_span.start)
        let end_line = byte_offset_to_line(contents, pt.byte_span.end)
        Test(
          module: module_name,
          name: pt.name,
          tags: pt.tags,
          file_path: path,
          line_span: LineSpan(start_line, end_line),
        )
      })
  }
}

pub fn parse_module(source: String) -> Result(List(ParsedTest), glance.Error) {
  parse_module_for_target(source, current_target())
}

pub fn parse_module_for_target(
  source: String,
  target: String,
) -> Result(List(ParsedTest), glance.Error) {
  glance.module(source)
  |> result.map(fn(module) {
    list.filter_map(module.functions, fn(def) {
      let func = def.definition
      case
        func.publicity,
        string.ends_with(func.name, "_test"),
        is_available_for_target(def.attributes, target)
      {
        glance.Public, True, True -> Ok(parse_function(func))
        glance.Private, _, _ | glance.Public, False, _ | glance.Public, _, False
        -> Error(Nil)
      }
    })
  })
}

fn is_available_for_target(
  attributes: List(glance.Attribute),
  target: String,
) -> Bool {
  let target_attrs = list.filter(attributes, fn(attr) { attr.name == "target" })

  case target_attrs {
    [] -> True
    attrs -> list.any(attrs, fn(attr) { matches_target(attr, target) })
  }
}

fn matches_target(attr: glance.Attribute, target: String) -> Bool {
  case attr.arguments {
    [glance.Variable(name: attr_target, ..)] -> attr_target == target
    _ -> True
  }
}

@target(erlang)
fn current_target() -> String {
  "erlang"
}

@target(javascript)
fn current_target() -> String {
  "javascript"
}

fn parse_function(func: glance.Function) -> ParsedTest {
  let tags = extract_tags_from_body(func.body)
  ParsedTest(name: func.name, tags: list.unique(tags), byte_span: func.location)
}

fn extract_tags_from_body(statements: List(glance.Statement)) -> List(String) {
  list.flat_map(statements, extract_tags_from_statement)
}

fn extract_tags_from_statement(stmt: glance.Statement) -> List(String) {
  case stmt {
    glance.Use(function: func, ..) -> extract_tags_from_expr(func)
    glance.Expression(expr) -> extract_tags_from_expr(expr)
    _ -> []
  }
}

fn extract_tags_from_expr(expr: glance.Expression) -> List(String) {
  case expr {
    // unitest.tag("slow")
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: "unitest", ..),
        label: "tag",
        ..,
      ),
      arguments: args,
      ..,
    ) -> extract_single_tag(args)

    // unitest.tags(["slow", "db"])
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: "unitest", ..),
        label: "tags",
        ..,
      ),
      arguments: args,
      ..,
    ) -> extract_tags_list(args)

    _ -> []
  }
}

fn extract_single_tag(
  args: List(glance.Field(glance.Expression)),
) -> List(String) {
  case args {
    [glance.UnlabelledField(glance.String(value: tag, ..))] -> [tag]
    _ -> []
  }
}

fn extract_tags_list(
  args: List(glance.Field(glance.Expression)),
) -> List(String) {
  case args {
    [glance.UnlabelledField(glance.List(elements: elements, ..))] ->
      list.filter_map(elements, fn(elem) {
        case elem {
          glance.String(value: tag, ..) -> Ok(tag)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}
