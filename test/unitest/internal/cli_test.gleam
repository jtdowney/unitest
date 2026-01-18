import gleam/option.{None, Some}
import gleam/string
import unitest/internal/cli

pub fn parse_empty_args_test() {
  let result = cli.parse([])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(location: cli.AllLocations, tag: None),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_seed_test() {
  // No file arg, just seed option
  let result = cli.parse(["--seed", "123"])
  assert result
    == Ok(cli.CliOptions(
      seed: Some(123),
      filter: cli.Filter(location: cli.AllLocations, tag: None),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_test_filter_test() {
  let result = cli.parse(["--test", "foo/bar_test.some_test"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyTest(module: "foo/bar_test", name: "some_test"),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_module_filter_test() {
  // --module is deprecated but still works, converts to OnlyFile internally
  let result = cli.parse(["--module", "foo/bar_test"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyFile("foo/bar_test.gleam"),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_tag_filter_test() {
  let result = cli.parse(["--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(location: cli.AllLocations, tag: Some("slow")),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn test_takes_precedence_over_module_test() {
  let result =
    cli.parse(["--test", "foo.bar_test", "--module", "baz", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyTest(module: "foo", name: "bar_test"),
        tag: Some("slow"),
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn module_and_tag_combined_test() {
  // --module converts to OnlyFile internally
  let result = cli.parse(["--module", "foo", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(location: cli.OnlyFile("foo.gleam"), tag: Some("slow")),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn seed_combined_with_filter_test() {
  let result = cli.parse(["--seed", "42", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: Some(42),
      filter: cli.Filter(location: cli.AllLocations, tag: Some("slow")),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_no_color_flag_test() {
  let result = cli.parse(["--no-color"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(location: cli.AllLocations, tag: None),
      no_color: True,
      reporter: cli.DotReporter,
    ))
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

pub fn parse_file_positional_arg_test() {
  let result = cli.parse(["test/foo_test.gleam"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyFile("test/foo_test.gleam"),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_file_with_line_positional_test() {
  let result = cli.parse(["test/foo_test.gleam:42"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyFileAtLine(path: "test/foo_test.gleam", line: 42),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_file_relative_path_test() {
  let result = cli.parse(["foo_test.gleam:10"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyFileAtLine(path: "foo_test.gleam", line: 10),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn parse_file_invalid_line_test() {
  let result = cli.parse(["foo_test.gleam:abc"])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid line number")
    Ok(_) -> False
  }
}

pub fn parse_file_zero_line_test() {
  let result = cli.parse(["foo_test.gleam:0"])
  assert case result {
    Error(msg) -> string.contains(msg, "must be positive")
    Ok(_) -> False
  }
}

pub fn parse_file_negative_line_test() {
  let result = cli.parse(["foo_test.gleam:-5"])
  assert case result {
    Error(msg) -> string.contains(msg, "must be positive")
    Ok(_) -> False
  }
}

pub fn test_takes_precedence_over_positional_file_test() {
  // Positional file first, then --test option
  let result = cli.parse(["baz.gleam", "--test", "foo.bar_test"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyTest(module: "foo", name: "bar_test"),
        tag: None,
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn positional_file_takes_precedence_over_module_test() {
  // Positional file first, then --module option
  let result = cli.parse(["foo.gleam", "--module", "bar"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(location: cli.OnlyFile("foo.gleam"), tag: None),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn file_and_tag_combined_test() {
  // Positional file first, then --tag option
  let result = cli.parse(["test/foo.gleam", "--tag", "slow"])
  assert result
    == Ok(cli.CliOptions(
      seed: None,
      filter: cli.Filter(
        location: cli.OnlyFile("test/foo.gleam"),
        tag: Some("slow"),
      ),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}

pub fn file_with_seed_test() {
  // Positional file first, then --seed option
  let result = cli.parse(["test/foo.gleam", "--seed", "42"])
  assert result
    == Ok(cli.CliOptions(
      seed: Some(42),
      filter: cli.Filter(location: cli.OnlyFile("test/foo.gleam"), tag: None),
      no_color: False,
      reporter: cli.DotReporter,
    ))
}
