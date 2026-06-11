import gleam/int
import gleam/list
import gleam/string
import qcheck
import simplifile
import unitest/internal/discovery

fn line_at(source: String, offset: Int) -> Int {
  discovery.byte_offset_to_line(discovery.newline_positions(source), offset)
}

fn parsed_test_name(t: discovery.ParsedTest) -> String {
  t.name
}

fn parsed_test_tags(t: discovery.ParsedTest) -> List(String) {
  t.tags
}

fn read_fixture(name: String) -> String {
  let assert Ok(source) = simplifile.read("test/fixtures/discovery/" <> name)
  source
}

fn sort_tests(tests: List(discovery.ParsedTest)) -> List(discovery.ParsedTest) {
  list.sort(tests, fn(a, b) { string.compare(a.name, b.name) })
}

pub fn byte_offset_to_line_always_positive_property_test() {
  let gen = qcheck.tuple2(qcheck.bounded_int(1, 100), qcheck.bounded_int(0, 50))
  use pair <- qcheck.given(gen)
  let #(line_count, offset_within) = pair
  let source =
    list.repeat("line", line_count)
    |> string.join("\n")
  let max_offset = string.byte_size(source) - 1
  let offset = int.clamp(offset_within, 0, int.max(0, max_offset))
  assert line_at(source, offset) >= 1
}

pub fn byte_offset_to_line_monotonic_test() {
  let source = "abcd\nabcd\nabcd"
  let first_newline = 4
  let second_newline = 9
  assert line_at(source, first_newline - 1) == 1
  assert line_at(source, first_newline + 1) == 2
  assert line_at(source, second_newline + 1) == 3
}

pub fn byte_offset_to_line_multibyte_test() {
  // Multiple multibyte characters: "日本" (6 bytes) + newline + "x"
  let source = "日本\nx"
  assert line_at(source, 0) == 1
  assert line_at(source, 6) == 1
  assert line_at(source, 7) == 2
}

pub fn byte_offset_to_line_offset_zero_is_line_one_property_test() {
  use line_count <- qcheck.given(qcheck.bounded_int(1, 100))
  let source =
    list.repeat("line", line_count)
    |> string.join("\n")
  assert line_at(source, 0) == 1
}

pub fn byte_offset_to_line_unicode_test() {
  // "日" is 3 bytes in UTF-8, so byte offset 4 is after the newline
  let source = "日\nline2"
  assert line_at(source, 0) == 1
  assert line_at(source, 3) == 1
  assert line_at(source, 4) == 2
}

pub fn detects_public_test_functions_test() {
  let assert Ok(tests) = discovery.parse_module(read_fixture("plain.gleam.txt"))
  let sorted = sort_tests(tests)
  assert list.map(sorted, parsed_test_name) == ["first_test", "second_test"]
  assert list.map(sorted, parsed_test_tags) == [[], []]
}

pub fn detects_tags_with_aliased_import_test() {
  let source = read_fixture("aliased_import.gleam.txt")
  let assert Ok([parsed]) = discovery.parse_module_for_target(source, "erlang")
  assert parsed_test_tags(parsed) == ["slow"]
}

pub fn detects_tags_with_unqualified_import_test() {
  let source = read_fixture("unqualified_import.gleam.txt")
  let assert Ok(tests) = discovery.parse_module_for_target(source, "erlang")
  let assert [a, b] = sort_tests(tests)
  assert parsed_test_tags(a) == ["db"]
  assert parsed_test_tags(b) == ["slow", "net"]
}

pub fn ignores_non_public_functions_test() {
  let result = discovery.parse_module(read_fixture("non_public.gleam.txt"))
  assert result == Ok([])
}

pub fn non_literal_tag_records_offset_test() {
  let source = read_fixture("non_literal_tag.gleam.txt")
  let assert Ok([parsed]) = discovery.parse_module_for_target(source, "erlang")
  assert parsed_test_tags(parsed) == []
  assert list.length(parsed.non_literal_tag_offsets) == 1
}

pub fn parse_module_captures_byte_spans_test() {
  let assert Ok(tests) = discovery.parse_module(read_fixture("plain.gleam.txt"))
  let sorted = sort_tests(tests)
  let assert [first, second] = sorted
  assert first.byte_span.start < second.byte_span.start
  assert first.byte_span.start == 0
}

pub fn parses_tags_per_function_test() {
  let assert Ok(tests) = discovery.parse_module(read_fixture("tags.gleam.txt"))
  let sorted = sort_tests(tests)
  assert list.map(sorted, parsed_test_name)
    == [
      "multiple_tags_test", "single_tag_test", "tags_list_test", "untagged_test",
    ]
  assert list.map(sorted, parsed_test_tags)
    == [["slow", "db"], ["slow"], ["slow", "integration"], []]
}

pub fn partition_discoveries_collects_failed_paths_test() {
  let results = [
    Ok(#([], [])),
    Error("test/bad_one.gleam"),
    Error("test/bad_two.gleam"),
  ]
  assert discovery.partition(results)
    == discovery.Discovery(
      tests: [],
      failed_paths: ["test/bad_one.gleam", "test/bad_two.gleam"],
      tag_warnings: [],
    )
}

pub fn partition_discoveries_collects_tag_warnings_test() {
  let results = [Ok(#([], ["test/a_test.gleam:4"])), Ok(#([], []))]
  assert discovery.partition(results)
    == discovery.Discovery(tests: [], failed_paths: [], tag_warnings: [
      "test/a_test.gleam:4",
    ])
}

pub fn partition_discoveries_returns_tests_in_input_order_test() {
  let first =
    discovery.Test(
      module: "a",
      name: "x_test",
      tags: [],
      file_path: "a.gleam",
      line_span: discovery.LineSpan(start_line: 1, end_line: 2),
    )
  let second =
    discovery.Test(
      module: "b",
      name: "y_test",
      tags: [],
      file_path: "b.gleam",
      line_span: discovery.LineSpan(start_line: 1, end_line: 2),
    )
  assert discovery.partition([Ok(#([first], [])), Ok(#([second], []))])
    == discovery.Discovery(
      tests: [first, second],
      failed_paths: [],
      tag_warnings: [],
    )
}

pub fn path_to_module_nested_test() {
  let path = "test/a/b/c_test.gleam"
  assert discovery.path_to_module(path) == "a/b/c_test"
}

pub fn path_to_module_simple_test() {
  let path = "test/foo/bar_test.gleam"
  assert discovery.path_to_module(path) == "foo/bar_test"
}

pub fn path_to_module_top_level_test() {
  let path = "test/my_test.gleam"
  assert discovery.path_to_module(path) == "my_test"
}

pub fn target_filter_keeps_erlang_only_test() {
  let assert Ok(tests) =
    discovery.parse_module_for_target(
      read_fixture("target_annotations.gleam.txt"),
      "erlang",
    )
  assert list.map(sort_tests(tests), parsed_test_name)
    == ["erlang_only_test", "plain_test"]
}

pub fn target_filter_keeps_javascript_only_test() {
  let assert Ok(tests) =
    discovery.parse_module_for_target(
      read_fixture("target_annotations.gleam.txt"),
      "javascript",
    )
  assert list.map(sort_tests(tests), parsed_test_name)
    == ["javascript_only_test", "plain_test"]
}
