import gleam/list
import gleam/string
import unitest/internal/discover

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
  let result = discover.parse_module(source)
  assert result == Ok([discover.ParsedTest(name: "example_test", tags: [])])
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
  assert sorted
    == [
      discover.ParsedTest(name: "alpha_test", tags: []),
      discover.ParsedTest(name: "beta_test", tags: []),
    ]
}

pub fn parse_single_tag_test() {
  let source =
    make_source(
      "tagged_test() {\n  use <- unitest.tag(\"slow\")\n  assert True\n}",
    )
  let result = discover.parse_module(source)
  assert result
    == Ok([discover.ParsedTest(name: "tagged_test", tags: ["slow"])])
}

pub fn parse_multiple_tags_test() {
  let source =
    make_source(
      "multi_tag_test() {\n  use <- unitest.tag(\"slow\")\n  use <- unitest.tag(\"db\")\n  assert True\n}",
    )
  let result = discover.parse_module(source)
  assert result
    == Ok([discover.ParsedTest(name: "multi_tag_test", tags: ["slow", "db"])])
}

pub fn parse_tags_list_test() {
  let source =
    make_source(
      "list_tag_test() {\n  use <- unitest.tags([\"slow\", \"integration\"])\n  assert True\n}",
    )
  let result = discover.parse_module(source)
  assert result
    == Ok([
      discover.ParsedTest(name: "list_tag_test", tags: ["slow", "integration"]),
    ])
}

pub fn tags_scoped_to_function_test() {
  let source =
    make_source(
      "scoped_a_test() {\n  use <- unitest.tag(\"slow\")\n  assert True\n}\n\n",
    )
    <> make_source("scoped_b_test() {\n  assert True\n}")
  let assert Ok(tests) = discover.parse_module(source)
  let sorted = sort_tests(tests)
  assert sorted
    == [
      discover.ParsedTest(name: "scoped_a_test", tags: ["slow"]),
      discover.ParsedTest(name: "scoped_b_test", tags: []),
    ]
}
