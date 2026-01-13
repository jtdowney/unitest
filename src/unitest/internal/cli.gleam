import clip
import clip/arg
import clip/flag
import clip/help
import clip/opt
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type LocationFilter {
  AllLocations
  OnlyTest(module: String, name: String)
  OnlyFile(path: String)
  OnlyFileAtLine(path: String, line: Int)
}

pub type Filter {
  Filter(location: LocationFilter, tag: Option(String))
}

pub type CliOptions {
  CliOptions(seed: Option(Int), filter: Filter, no_color: Bool)
}

pub fn parse(args: List(String)) -> Result(CliOptions, String) {
  let command =
    clip.command({
      use seed_result <- clip.parameter
      use test_result <- clip.parameter
      use module_result <- clip.parameter
      use tag_result <- clip.parameter
      use no_color <- clip.parameter
      use file_result <- clip.parameter

      let seed = case seed_result {
        Ok(s) -> Some(s)
        Error(Nil) -> None
      }
      #(file_result, seed, test_result, module_result, tag_result, no_color)
    })
    |> clip.opt(
      opt.new("seed")
      |> opt.help("Set random seed for reproducible test ordering")
      |> opt.int
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("test")
      |> opt.help("Run a single test (format: wibble/wobble_test.name_test)")
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("module")
      |> opt.help("[Deprecated] Run all tests in a module")
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("tag")
      |> opt.help("Run tests with a specific tag")
      |> opt.optional,
    )
    |> clip.flag(flag.new("no-color") |> flag.help("Disable colored output"))
    |> clip.arg(
      arg.new("file")
      |> arg.help(
        "Run tests in a specific file (optionally with line number, e.g., file.gleam:10)",
      )
      |> arg.optional,
    )

  use #(file_result, seed, test_result, module_result, tag_result, no_color) <- result.try(
    command
    |> clip.help(help.simple("unitest", "Simple unit testing framework"))
    |> clip.run(args),
  )

  use filter <- result.try(resolve_filter(
    test_result,
    file_result,
    module_result,
    tag_result,
  ))
  Ok(CliOptions(seed: seed, filter: filter, no_color: no_color))
}

fn resolve_filter(
  test_result: Result(String, Nil),
  file_result: Result(String, Nil),
  module_result: Result(String, Nil),
  tag_result: Result(String, Nil),
) -> Result(Filter, String) {
  // Location filter with precedence: --test > positional file > --module (deprecated)
  use location <- result.try(case test_result, file_result, module_result {
    Ok(test_str), _, _ -> parse_test_filter(test_str)
    _, Ok(file_str), _ -> parse_file_filter(file_str)
    _, _, Ok(module) -> Ok(OnlyFile(module <> ".gleam"))
    _, _, _ -> Ok(AllLocations)
  })

  // Tag is independent, can combine with any location
  let tag = case tag_result {
    Ok(t) -> Some(t)
    Error(Nil) -> None
  }

  Ok(Filter(location: location, tag: tag))
}

fn parse_test_filter(test_str: String) -> Result(LocationFilter, String) {
  case string.split_once(test_str, ".") {
    Ok(#(module, name)) -> Ok(OnlyTest(module: module, name: name))
    Error(Nil) ->
      Error(
        "Invalid --test format: '"
        <> test_str
        <> "'. Expected: module/path.function_name",
      )
  }
}

fn parse_file_filter(file_str: String) -> Result(LocationFilter, String) {
  case string.split_once(file_str, ":") {
    Ok(#(path, line_str)) ->
      case int.parse(line_str) {
        Ok(line) if line > 0 -> Ok(OnlyFileAtLine(path: path, line: line))
        Ok(_) ->
          Error(
            "Line number must be positive in file filter: '" <> line_str <> "'",
          )
        Error(_) ->
          Error("Invalid line number in file filter: '" <> line_str <> "'")
      }
    Error(Nil) -> Ok(OnlyFile(path: file_str))
  }
}
