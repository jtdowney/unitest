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

pub type Reporter {
  DotReporter
  TableReporter
}

pub type SortOrder {
  NativeSort
  TimeSort
  NameSort
}

pub type CliOptions {
  CliOptions(
    seed: Option(Int),
    filter: Filter,
    no_color: Bool,
    reporter: Reporter,
    sort_order: Option(SortOrder),
    sort_reversed: Bool,
    workers: Option(Int),
  )
}

pub fn parse(args: List(String)) -> Result(CliOptions, String) {
  let command =
    clip.command({
      use seed_result <- clip.parameter
      use test_result <- clip.parameter
      use module_result <- clip.parameter
      use tag_result <- clip.parameter
      use no_color <- clip.parameter
      use reporter_str <- clip.parameter
      use sort_str <- clip.parameter
      use sort_rev <- clip.parameter
      use workers_result <- clip.parameter
      use file_result <- clip.parameter

      let seed = option.from_result(seed_result)
      let workers = option.from_result(workers_result)
      #(
        file_result,
        seed,
        test_result,
        module_result,
        tag_result,
        no_color,
        reporter_str,
        sort_str,
        sort_rev,
        workers,
      )
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
    |> clip.opt(
      opt.new("reporter")
      |> opt.help("Output format: dot (default) or table")
      |> opt.default("dot"),
    )
    |> clip.opt(
      opt.new("sort")
      |> opt.help("Sort order for table reporter: native, time, or name")
      |> opt.optional,
    )
    |> clip.flag(
      flag.new("sort-rev")
      |> flag.help("Reverse the sort order (table reporter only)"),
    )
    |> clip.opt(
      opt.new("workers")
      |> opt.help("Number of module groups to run in parallel")
      |> opt.int
      |> opt.optional,
    )
    |> clip.arg(
      arg.new("file")
      |> arg.help(
        "Run tests in a specific file (optionally with line number, e.g., file.gleam:10)",
      )
      |> arg.optional,
    )

  use
    #(
      file_result,
      seed,
      test_result,
      module_result,
      tag_result,
      no_color,
      reporter_str,
      sort_str,
      sort_rev,
      workers,
    )
  <- result.try(
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
  use reporter <- result.try(parse_reporter(reporter_str))
  use sort_order <- result.try(parse_sort_order(sort_str))
  use validated_workers <- result.try(validate_workers(workers))
  Ok(CliOptions(
    seed:,
    filter:,
    no_color:,
    reporter:,
    sort_order:,
    sort_reversed: sort_rev,
    workers: validated_workers,
  ))
}

fn parse_reporter(reporter_str: String) -> Result(Reporter, String) {
  case reporter_str {
    "dot" -> Ok(DotReporter)
    "table" -> Ok(TableReporter)
    other -> Error("Invalid reporter: '" <> other <> "'. Use 'dot' or 'table'")
  }
}

fn parse_sort_order(
  sort_result: Result(String, Nil),
) -> Result(Option(SortOrder), String) {
  case sort_result {
    Error(Nil) -> Ok(None)
    Ok("native") -> Ok(Some(NativeSort))
    Ok("time") -> Ok(Some(TimeSort))
    Ok("name") -> Ok(Some(NameSort))
    Ok(other) ->
      Error(
        "Invalid sort order: '" <> other <> "'. Use 'native', 'time', or 'name'",
      )
  }
}

fn validate_workers(workers: Option(Int)) -> Result(Option(Int), String) {
  case workers {
    Some(n) if n <= 0 -> Error("Workers must be positive")
    _ -> Ok(workers)
  }
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

  Ok(Filter(location:, tag: option.from_result(tag_result)))
}

fn parse_test_filter(test_str: String) -> Result(LocationFilter, String) {
  case string.split_once(test_str, ".") {
    Ok(#(module, name)) if module != "" && name != "" ->
      Ok(OnlyTest(module: module, name: name))
    _ ->
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
