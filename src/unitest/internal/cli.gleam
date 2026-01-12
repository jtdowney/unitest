import clip
import clip/flag
import clip/help
import clip/opt
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Filter {
  All
  OnlyTest(module: String, name: String)
  OnlyModule(String)
  OnlyTag(String)
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

      let seed = case seed_result {
        Ok(s) -> Some(s)
        Error(Nil) -> None
      }
      #(seed, test_result, module_result, tag_result, no_color)
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
      |> opt.help("Run all tests in a module")
      |> opt.optional,
    )
    |> clip.opt(
      opt.new("tag")
      |> opt.help("Run tests with a specific tag")
      |> opt.optional,
    )
    |> clip.flag(flag.new("no-color") |> flag.help("Disable colored output"))

  use #(seed, test_result, module_result, tag_result, no_color) <- result.try(
    command
    |> clip.help(help.simple("unitest", "Simple unit testing framework"))
    |> clip.run(args),
  )
  use filter <- result.try(resolve_filter(
    test_result,
    module_result,
    tag_result,
  ))
  Ok(CliOptions(seed: seed, filter: filter, no_color: no_color))
}

fn resolve_filter(
  test_result: Result(String, Nil),
  module_result: Result(String, Nil),
  tag_result: Result(String, Nil),
) -> Result(Filter, String) {
  case test_result, module_result, tag_result {
    Ok(test_str), _, _ -> parse_test_filter(test_str)
    _, Ok(module), _ -> Ok(OnlyModule(module))
    _, _, Ok(tag) -> Ok(OnlyTag(tag))
    _, _, _ -> Ok(All)
  }
}

fn parse_test_filter(test_str: String) -> Result(Filter, String) {
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
