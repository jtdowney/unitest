import gleam/option.{None, Some}
import gleam/string
import unitest/internal/cli

pub fn parse_empty_args_test() {
  let result = cli.parse([])
  assert result
    == Ok(cli.CliOptions(seed: None, filter: cli.All, no_color: False))
}

pub fn parse_seed_test() {
  let result = cli.parse(["--seed", "123"])
  assert result
    == Ok(cli.CliOptions(seed: Some(123), filter: cli.All, no_color: False))
}

pub fn parse_test_filter_test() {
  let result = cli.parse(["--test", "foo/bar_test.some_test"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.OnlyTest(module: "foo/bar_test", name: "some_test"),
      no_color: False,
    ))
}

pub fn parse_module_filter_test() {
  let result = cli.parse(["--module", "foo/bar_test"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.OnlyModule("foo/bar_test"),
      no_color: False,
    ))
}

pub fn parse_tag_filter_test() {
  let result = cli.parse(["--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.OnlyTag("slow"),
      no_color: False,
    ))
}

pub fn test_takes_precedence_over_module_test() {
  let result =
    cli.parse(["--test", "foo.bar_test", "--module", "baz", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.OnlyTest(module: "foo", name: "bar_test"),
      no_color: False,
    ))
}

pub fn module_takes_precedence_over_tag_test() {
  let result = cli.parse(["--module", "foo", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.OnlyModule("foo"),
      no_color: False,
    ))
}

pub fn seed_combined_with_filter_test() {
  let result = cli.parse(["--seed", "42", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: Some(42),
      filter: cli.OnlyTag("slow"),
      no_color: False,
    ))
}

pub fn parse_no_color_flag_test() {
  let result = cli.parse(["--no-color"])
  assert result
    == Ok(cli.CliOptions(seed: None, filter: cli.All, no_color: True))
}

pub fn parse_invalid_test_filter_missing_dot_test() {
  let result = cli.parse(["--test", "foo_test"])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid --test format")
    Ok(_) -> False
  }
}

pub fn parse_invalid_test_filter_no_function_test() {
  let result = cli.parse(["--test", "some/module"])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid --test format")
    Ok(_) -> False
  }
}
