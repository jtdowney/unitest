import glance
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

const gleam_extension = ".gleam"

const test_directory = "test"

@external(javascript, "../../unitest_ffi.mjs", "currentTarget")
fn current_target() -> String {
  "erlang"
}

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
  ParsedTest(
    name: String,
    tags: List(String),
    byte_span: glance.Span,
    non_literal_tag_offsets: List(Int),
  )
}

pub type Discovery {
  Discovery(
    tests: List(Test),
    failed_paths: List(String),
    tag_warnings: List(String),
  )
}

pub fn path_to_module(path: String) -> String {
  let prefix_length = string.length(test_directory) + 1
  path
  |> string.drop_start(prefix_length)
  |> string.drop_end(string.length(gleam_extension))
}

pub fn newline_positions(source: String) -> List(Int) {
  newline_positions_loop(bit_array.from_string(source), 0, [])
}

fn newline_positions_loop(
  bytes: BitArray,
  position: Int,
  acc: List(Int),
) -> List(Int) {
  case bytes {
    <<0x0A, rest:bits>> ->
      newline_positions_loop(rest, position + 1, [position, ..acc])
    <<_byte, rest:bits>> -> newline_positions_loop(rest, position + 1, acc)
    _ -> list.reverse(acc)
  }
}

pub fn byte_offset_to_line(newlines: List(Int), byte_offset: Int) -> Int {
  list.count(newlines, fn(position) { position < byte_offset }) + 1
}

pub fn from_fs() -> Result(Discovery, simplifile.FileError) {
  use files <- result.map(simplifile.get_files(test_directory))
  files
  |> list.filter(string.ends_with(_, gleam_extension))
  |> list.map(discover_tests_in_file)
  |> partition
}

pub fn partition(
  results: List(Result(#(List(Test), List(String)), String)),
) -> Discovery {
  let #(discoveries, failed) = result.partition(results)
  let #(test_lists, warning_lists) = list.unzip(discoveries)
  Discovery(
    tests: list.flatten(list.reverse(test_lists)),
    failed_paths: list.reverse(failed),
    tag_warnings: list.flatten(list.reverse(warning_lists)),
  )
}

fn discover_tests_in_file(
  path: String,
) -> Result(#(List(Test), List(String)), String) {
  let module_name = path_to_module(path)

  case simplifile.read(path) {
    Error(_) -> Ok(#([], []))
    Ok(contents) -> tests_from_contents(path, module_name, contents)
  }
}

fn tests_from_contents(
  path: String,
  module_name: String,
  contents: String,
) -> Result(#(List(Test), List(String)), String) {
  use parsed <- result.try(parse_module(contents) |> result.replace_error(path))
  let newlines = newline_positions(contents)
  let tests =
    list.map(parsed, fn(test_) {
      let start_line = byte_offset_to_line(newlines, test_.byte_span.start)
      let end_line = byte_offset_to_line(newlines, test_.byte_span.end)
      Test(
        module: module_name,
        name: test_.name,
        tags: test_.tags,
        file_path: path,
        line_span: LineSpan(start_line, end_line),
      )
    })
  let warnings =
    list.flat_map(parsed, fn(test_) {
      list.map(test_.non_literal_tag_offsets, fn(offset) {
        path <> ":" <> int.to_string(byte_offset_to_line(newlines, offset))
      })
    })

  Ok(#(tests, warnings))
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
    let syntax = resolve_tag_syntax(module)
    list.filter_map(module.functions, fn(def) {
      let func = def.definition
      case func.publicity, string.ends_with(func.name, "_test") {
        glance.Public, True ->
          case is_available_for_target(def.attributes, target) {
            True -> Ok(parse_function(func, syntax))
            False -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    })
  })
}

type TagSyntax {
  TagSyntax(
    module_name: Option(String),
    tag_name: Option(String),
    tags_name: Option(String),
  )
}

fn resolve_tag_syntax(module: glance.Module) -> TagSyntax {
  case
    list.find(module.imports, fn(def) { def.definition.module == "unitest" })
  {
    Error(Nil) ->
      TagSyntax(
        module_name: option.Some("unitest"),
        tag_name: option.None,
        tags_name: option.None,
      )
    Ok(def) ->
      TagSyntax(
        module_name: imported_module_name(def.definition.alias),
        tag_name: unqualified_local_name(
          def.definition.unqualified_values,
          "tag",
        ),
        tags_name: unqualified_local_name(
          def.definition.unqualified_values,
          "tags",
        ),
      )
  }
}

fn imported_module_name(
  alias: Option(glance.AssignmentName),
) -> Option(String) {
  case alias {
    option.None -> option.Some("unitest")
    option.Some(glance.Named(name)) -> option.Some(name)
    option.Some(glance.Discarded(_)) -> option.None
  }
}

fn unqualified_local_name(
  imports: List(glance.UnqualifiedImport),
  name: String,
) -> Option(String) {
  case list.find(imports, fn(import_) { import_.name == name }) {
    Ok(glance.UnqualifiedImport(alias: option.Some(alias), ..)) ->
      option.Some(alias)
    Ok(glance.UnqualifiedImport(alias: option.None, name: local_name)) ->
      option.Some(local_name)
    Error(Nil) -> option.None
  }
}

fn is_available_for_target(
  attributes: List(glance.Attribute),
  target: String,
) -> Bool {
  case list.find(attributes, fn(attr) { attr.name == "target" }) {
    Error(Nil) -> True
    Ok(glance.Attribute(arguments: [glance.Variable(name:, ..)], ..)) ->
      name == target
    Ok(_) -> True
  }
}

type TagExtraction {
  TagExtraction(tags: List(String), non_literal_offsets: List(Int))
}

const no_tags = TagExtraction(tags: [], non_literal_offsets: [])

fn parse_function(func: glance.Function, syntax: TagSyntax) -> ParsedTest {
  let extractions = list.map(func.body, extract_tags_from_statement(_, syntax))
  let tags =
    extractions
    |> list.flat_map(fn(extraction) { extraction.tags })
    |> list.unique
  let non_literal_tag_offsets =
    list.flat_map(extractions, fn(extraction) { extraction.non_literal_offsets })
  ParsedTest(
    name: func.name,
    tags:,
    byte_span: func.location,
    non_literal_tag_offsets:,
  )
}

fn extract_tags_from_statement(
  stmt: glance.Statement,
  syntax: TagSyntax,
) -> TagExtraction {
  case stmt {
    glance.Use(function: func, ..) -> extract_tags_from_expr(func, syntax)
    glance.Expression(expr) -> extract_tags_from_expr(expr, syntax)
    _ -> no_tags
  }
}

fn extract_tags_from_expr(
  expr: glance.Expression,
  syntax: TagSyntax,
) -> TagExtraction {
  case expr {
    glance.Call(
      function: glance.FieldAccess(
        container: glance.Variable(name: module_name, ..),
        label:,
        ..,
      ),
      arguments: args,
      location:,
    ) ->
      case option.Some(module_name) == syntax.module_name {
        True -> extract_qualified_call(label, args, location)
        False -> no_tags
      }
    glance.Call(
      function: glance.Variable(name:, ..),
      arguments: args,
      location:,
    ) -> extract_unqualified_call(name, args, location, syntax)
    _ -> no_tags
  }
}

fn extract_qualified_call(
  label: String,
  args: List(glance.Field(glance.Expression)),
  location: glance.Span,
) -> TagExtraction {
  case label {
    "tag" -> extract_single_tag(args, location)
    "tags" -> extract_tags_list(args, location)
    _ -> no_tags
  }
}

fn extract_unqualified_call(
  name: String,
  args: List(glance.Field(glance.Expression)),
  location: glance.Span,
  syntax: TagSyntax,
) -> TagExtraction {
  case
    option.Some(name) == syntax.tag_name,
    option.Some(name) == syntax.tags_name
  {
    True, _ -> extract_single_tag(args, location)
    False, True -> extract_tags_list(args, location)
    False, False -> no_tags
  }
}

fn extract_single_tag(
  args: List(glance.Field(glance.Expression)),
  location: glance.Span,
) -> TagExtraction {
  case args {
    [glance.UnlabelledField(glance.String(value: tag, ..)), ..] ->
      TagExtraction(tags: [tag], non_literal_offsets: [])
    _ -> TagExtraction(tags: [], non_literal_offsets: [location.start])
  }
}

fn extract_tags_list(
  args: List(glance.Field(glance.Expression)),
  location: glance.Span,
) -> TagExtraction {
  case args {
    [glance.UnlabelledField(glance.List(elements:, ..)), ..] ->
      tags_from_elements(elements, location)
    _ -> TagExtraction(tags: [], non_literal_offsets: [location.start])
  }
}

fn tags_from_elements(
  elements: List(glance.Expression),
  location: glance.Span,
) -> TagExtraction {
  let tags =
    list.filter_map(elements, fn(element) {
      case element {
        glance.String(value: tag, ..) -> Ok(tag)
        _ -> Error(Nil)
      }
    })
  case list.length(tags) == list.length(elements) {
    True -> TagExtraction(tags:, non_literal_offsets: [])
    False -> TagExtraction(tags:, non_literal_offsets: [location.start])
  }
}
