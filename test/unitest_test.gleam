import gleam/list
import gleam/option.{None}
import unitest
import unitest/internal/cli
import unitest/internal/runner.{Report}

pub fn main() -> Nil {
  unitest.main()
}

pub fn exit_code_zero_when_no_failures_test() {
  let report =
    Report(
      passed: 5,
      failed: 0,
      skipped: 1,
      failures: [],
      seed: 1,
      runtime_ms: 100,
    )
  assert unitest.exit_code(report) == 0
}

pub fn exit_code_one_when_failures_test() {
  let report =
    Report(
      passed: 4,
      failed: 1,
      skipped: 0,
      failures: [],
      seed: 1,
      runtime_ms: 100,
    )
  assert unitest.exit_code(report) == 1
}

pub fn parse_package_name_extracts_name_test() {
  let content = "name = \"unitest\"\nversion = \"1.0.0\""
  assert unitest.parse_package_name(content) == Ok("unitest")
}

pub fn parse_package_name_with_leading_whitespace_test() {
  let content = "  name = \"mypackage\"\n"
  assert unitest.parse_package_name(content) == Ok("mypackage")
}

pub fn parse_package_name_finds_first_name_line_test() {
  let content = "description = \"test\"\nname = \"found\"\nother = \"stuff\""
  assert unitest.parse_package_name(content) == Ok("found")
}

pub fn parse_package_name_missing_name_returns_error_test() {
  let content = "version = \"1.0.0\"\ndescription = \"no name here\""
  assert unitest.parse_package_name(content) == Error(Nil)
}

pub fn parse_package_name_malformed_line_returns_error_test() {
  let content = "name = noquotes"
  assert unitest.parse_package_name(content) == Error(Nil)
}

pub fn parse_package_name_empty_content_returns_error_test() {
  assert unitest.parse_package_name("") == Error(Nil)
}

pub fn default_options_returns_expected_defaults_test() {
  let opts = unitest.default_options()
  assert opts.seed == None
  assert list.is_empty(opts.ignored_tags)
  assert opts.test_directory == "test"
  assert opts.sort_order == cli.NativeSort
  assert opts.sort_reversed == False
  assert opts.check_results == False
}

pub fn guard_is_lazyily_evaluated_test() {
  use <- unitest.guard(True)
  let success = True
  assert success
}
