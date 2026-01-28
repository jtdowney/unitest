import gleam/int
import gleam/list
import gleam/string
import qcheck
import unitest/internal/discover

fn parsed_test_name(t: discover.ParsedTest) -> String {
  t.name
}

fn parsed_test_tags(t: discover.ParsedTest) -> List(String) {
  t.tags
}

pub fn path_to_module_simple_test() {
  let path = "test/foo/bar_test.gleam"
  assert discover.path_to_module(path, "test") == "foo/bar_test"
}

pub fn path_to_module_nested_test() {
  let path = "test/a/b/c_test.gleam"
  assert discover.path_to_module(path, "test") == "a/b/c_test"
}

pub fn path_to_module_top_level_test() {
  let path = "test/my_test.gleam"
  assert discover.path_to_module(path, "test") == "my_test"
}

pub fn path_to_module_custom_dir_test() {
  let path = "custom_tests/foo/bar_test.gleam"
  assert discover.path_to_module(path, "custom_tests") == "foo/bar_test"
}

pub fn path_to_module_nested_custom_dir_test() {
  let path = "specs/unit/model_test.gleam"
  assert discover.path_to_module(path, "specs/unit") == "model_test"
}

fn make_source(body: String) -> String {
  string.concat(["pub", " fn ", body])
}

fn sort_tests(tests: List(discover.ParsedTest)) -> List(discover.ParsedTest) {
  list.sort(tests, fn(a, b) { string.compare(a.name, b.name) })
}

pub fn detect_pub_fn_test() {
  let source = make_source("example_test() {\n  assert True\n}")
  let assert Ok([t]) = discover.parse_module(source)
  assert t.name == "example_test"
  assert list.is_empty(t.tags)
}

pub fn ignore_non_public_fn_test() {
  let source = "fn private_test() {\n  assert True\n}"
  let result = discover.parse_module(source)
  assert result == Ok([])
}

pub fn detect_multiple_tests_test() {
  let source =
    make_source("alpha_test() { }\n") <> make_source("beta_test() { }")
  let assert Ok(tests) = discover.parse_module(source)
  let sorted = sort_tests(tests)
  assert list.map(sorted, parsed_test_name) == ["alpha_test", "beta_test"]
  assert list.map(sorted, parsed_test_tags) == [[], []]
}

pub fn parse_single_tag_test() {
  let source =
    make_source(
      "tagged_test() {\n  use <- unitest.tag(\"slow\")\n  assert True\n}",
    )
  let assert Ok([t]) = discover.parse_module(source)
  assert t.name == "tagged_test"
  assert t.tags == ["slow"]
}

pub fn parse_multiple_tags_test() {
  let source =
    make_source(
      "multi_tag_test() {\n  use <- unitest.tag(\"slow\")\n  use <- unitest.tag(\"db\")\n  assert True\n}",
    )
  let assert Ok([t]) = discover.parse_module(source)
  assert t.name == "multi_tag_test"
  assert t.tags == ["slow", "db"]
}

pub fn parse_tags_list_test() {
  let source =
    make_source(
      "list_tag_test() {\n  use <- unitest.tags([\"slow\", \"integration\"])\n  assert True\n}",
    )
  let assert Ok([t]) = discover.parse_module(source)
  assert t.name == "list_tag_test"
  assert t.tags == ["slow", "integration"]
}

pub fn tags_scoped_to_function_test() {
  let source =
    make_source(
      "scoped_a_test() {\n  use <- unitest.tag(\"slow\")\n  assert True\n}\n\n",
    )
    <> make_source("scoped_b_test() {\n  assert True\n}")
  let assert Ok(tests) = discover.parse_module(source)
  let sorted = sort_tests(tests)
  assert list.map(sorted, parsed_test_name)
    == ["scoped_a_test", "scoped_b_test"]
  assert list.map(sorted, parsed_test_tags) == [["slow"], []]
}

pub fn byte_offset_to_line_always_positive_property_test() {
  let gen = qcheck.tuple2(qcheck.bounded_int(1, 100), qcheck.bounded_int(0, 50))
  qcheck.run(qcheck.default_config(), gen, fn(pair) {
    let #(line_count, offset_within) = pair
    let source =
      list.repeat("line", line_count)
      |> string.join("\n")
    let max_offset = string.byte_size(source) - 1
    let offset = int.clamp(offset_within, 0, int.max(0, max_offset))
    assert discover.byte_offset_to_line(source, offset) >= 1
  })
}

pub fn byte_offset_to_line_offset_zero_is_line_one_property_test() {
  qcheck.run(
    qcheck.default_config(),
    qcheck.bounded_int(1, 100),
    fn(line_count) {
      let source =
        list.repeat("line", line_count)
        |> string.join("\n")
      assert discover.byte_offset_to_line(source, 0) == 1
    },
  )
}

pub fn byte_offset_to_line_monotonic_property_test() {
  qcheck.run(qcheck.default_config(), qcheck.bounded_int(2, 50), fn(line_count) {
    let source =
      list.repeat("abcd", line_count)
      |> string.join("\n")
    let first_newline = 4
    let second_newline = 9
    let before_first = discover.byte_offset_to_line(source, first_newline - 1)
    let after_first = discover.byte_offset_to_line(source, first_newline + 1)
    let after_second = discover.byte_offset_to_line(source, second_newline + 1)
    assert before_first == 1
    assert after_first == 2
    assert after_second >= after_first
  })
}

pub fn parse_module_captures_byte_spans_test() {
  let source =
    "pub fn first_test() {\n  Nil\n}\n\npub fn second_test() {\n  Nil\n}"
  let assert Ok(tests) = discover.parse_module(source)
  let sorted = sort_tests(tests)
  assert list.length(sorted) == 2
  let assert [first, second] = sorted
  assert first.byte_span.start < second.byte_span.start
  assert first.byte_span.start == 0
}

pub fn byte_offset_to_line_unicode_test() {
  // "日" is 3 bytes in UTF-8, so byte offset 4 is after the newline
  let source = "日\nline2"
  assert discover.byte_offset_to_line(source, 0) == 1
  assert discover.byte_offset_to_line(source, 3) == 1
  assert discover.byte_offset_to_line(source, 4) == 2
}

pub fn byte_offset_to_line_multibyte_test() {
  // Multiple multibyte characters: "日本" (6 bytes) + newline + "x"
  let source = "日本\nx"
  assert discover.byte_offset_to_line(source, 0) == 1
  assert discover.byte_offset_to_line(source, 6) == 1
  assert discover.byte_offset_to_line(source, 7) == 2
}
