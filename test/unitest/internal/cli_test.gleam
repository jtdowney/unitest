import gleam/option.{None, Some}
import gleam/string
import unitest/internal/cli

fn default_opts() -> cli.CliOptions {
  cli.CliOptions(
    seed: None,
    filter: cli.Filter(location: cli.AllLocations, tag: None),
    no_color: False,
    reporter: cli.DotReporter,
    sort_order: None,
    sort_reversed: False,
    workers: None,
  )
}

pub fn parse_empty_args_test() {
  let result = cli.parse([])
  assert result == Ok(default_opts())
}

pub fn parse_seed_test() {
  let result = cli.parse(["--seed", "123"])
  assert result == Ok(cli.CliOptions(..default_opts(), seed: Some(123)))
}

pub fn parse_test_filter_test() {
  let result = cli.parse(["--test", "foo/bar_test.some_test"])
  let filter =
    cli.Filter(
      location: cli.OnlyTest(module: "foo/bar_test", name: "some_test"),
      tag: None,
    )
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn parse_module_filter_test() {
  let result = cli.parse(["--module", "foo/bar_test"])
  let filter =
    cli.Filter(location: cli.OnlyFile("foo/bar_test.gleam"), tag: None)
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn parse_tag_filter_test() {
  let result = cli.parse(["--tag", "slow"])
  let filter = cli.Filter(location: cli.AllLocations, tag: Some("slow"))
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn test_takes_precedence_over_module_test() {
  let result =
    cli.parse(["--test", "foo.bar_test", "--module", "baz", "--tag", "slow"])
  let filter =
    cli.Filter(
      location: cli.OnlyTest(module: "foo", name: "bar_test"),
      tag: Some("slow"),
    )
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn module_and_tag_combined_test() {
  let result = cli.parse(["--module", "foo", "--tag", "slow"])
  let filter =
    cli.Filter(location: cli.OnlyFile("foo.gleam"), tag: Some("slow"))
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn seed_combined_with_filter_test() {
  let result = cli.parse(["--seed", "42", "--tag", "slow"])
  let filter = cli.Filter(location: cli.AllLocations, tag: Some("slow"))
  assert result == Ok(cli.CliOptions(..default_opts(), seed: Some(42), filter:))
}

pub fn parse_no_color_flag_test() {
  let result = cli.parse(["--no-color"])
  assert result == Ok(cli.CliOptions(..default_opts(), no_color: True))
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

pub fn parse_invalid_test_filter_empty_function_test() {
  let result = cli.parse(["--test", "foo."])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid --test format")
    Ok(_) -> False
  }
}

pub fn parse_invalid_test_filter_empty_module_test() {
  let result = cli.parse(["--test", ".bar_test"])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid --test format")
    Ok(_) -> False
  }
}

pub fn parse_invalid_test_filter_dot_only_test() {
  let result = cli.parse(["--test", "."])
  assert case result {
    Error(msg) -> string.contains(msg, "Invalid --test format")
    Ok(_) -> False
  }
}

pub fn parse_file_positional_arg_test() {
  let result = cli.parse(["test/foo_test.gleam"])
  let filter =
    cli.Filter(location: cli.OnlyFile("test/foo_test.gleam"), tag: None)
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_with_line_positional_test() {
  let result = cli.parse(["test/foo_test.gleam:42"])
  let filter =
    cli.Filter(
      location: cli.OnlyFileAtLine(path: "test/foo_test.gleam", line: 42),
      tag: None,
    )
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn parse_file_relative_path_test() {
  let result = cli.parse(["foo_test.gleam:10"])
  let filter =
    cli.Filter(
      location: cli.OnlyFileAtLine(path: "foo_test.gleam", line: 10),
      tag: None,
    )
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
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
  let result = cli.parse(["baz.gleam", "--test", "foo.bar_test"])
  let filter =
    cli.Filter(
      location: cli.OnlyTest(module: "foo", name: "bar_test"),
      tag: None,
    )
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn positional_file_takes_precedence_over_module_test() {
  let result = cli.parse(["foo.gleam", "--module", "bar"])
  let filter = cli.Filter(location: cli.OnlyFile("foo.gleam"), tag: None)
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn file_and_tag_combined_test() {
  let result = cli.parse(["test/foo.gleam", "--tag", "slow"])
  let filter =
    cli.Filter(location: cli.OnlyFile("test/foo.gleam"), tag: Some("slow"))
  assert result == Ok(cli.CliOptions(..default_opts(), filter:))
}

pub fn file_with_seed_test() {
  let result = cli.parse(["test/foo.gleam", "--seed", "42"])
  let filter = cli.Filter(location: cli.OnlyFile("test/foo.gleam"), tag: None)
  assert result == Ok(cli.CliOptions(..default_opts(), seed: Some(42), filter:))
}

pub fn parse_reporter_table_test() {
  let result = cli.parse(["--reporter", "table"])
  assert result
    == Ok(cli.CliOptions(..default_opts(), reporter: cli.TableReporter))
}

pub fn parse_sort_time_test() {
  let result = cli.parse(["--sort", "time"])
  assert result
    == Ok(cli.CliOptions(..default_opts(), sort_order: Some(cli.TimeSort)))
}

pub fn parse_sort_name_test() {
  let result = cli.parse(["--sort", "name"])
  assert result
    == Ok(cli.CliOptions(..default_opts(), sort_order: Some(cli.NameSort)))
}

pub fn parse_workers_test() {
  let result = cli.parse(["--workers", "4"])
  assert result == Ok(cli.CliOptions(..default_opts(), workers: Some(4)))
}

pub fn parse_workers_must_be_positive_test() {
  let result = cli.parse(["--workers", "0"])
  assert case result {
    Error(msg) -> string.contains(msg, "Workers must be positive")
    Ok(_) -> False
  }
}

pub fn parse_workers_negative_test() {
  let result = cli.parse(["--workers", "-1"])
  assert case result {
    Error(msg) -> string.contains(msg, "Workers must be positive")
    Ok(_) -> False
  }
}
