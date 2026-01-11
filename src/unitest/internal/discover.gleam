import glance.{
  type Expression, type Function, type Statement, Call,
  Expression as ExprStatement, FieldAccess, List as ListExpr, Public,
  String as StringExpr, UnlabelledField, Use, Variable,
}
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type Test {
  Test(module: String, name: String, tags: List(String))
}

pub type ParsedTest {
  ParsedTest(name: String, tags: List(String))
}

pub fn path_to_module(path: String) -> String {
  path
  |> string.drop_start(5)
  |> string.drop_end(6)
}

pub fn discover_from_fs(base_path: String) -> List(Test) {
  simplifile.get_files(base_path)
  |> result.unwrap([])
  |> list.filter(string.ends_with(_, ".gleam"))
  |> list.flat_map(discover_tests_in_file)
}

fn discover_tests_in_file(path: String) -> List(Test) {
  let module_name = path_to_module(path)

  case simplifile.read(path) {
    Error(_) -> []
    Ok(contents) ->
      parse_module(contents)
      |> result.unwrap([])
      |> list.map(fn(pt) {
        Test(module: module_name, name: pt.name, tags: pt.tags)
      })
  }
}

pub fn parse_module(source: String) -> Result(List(ParsedTest), glance.Error) {
  use module <- result.try(glance.module(source))

  let tests =
    module.functions
    |> list.filter_map(fn(def) {
      let func = def.definition
      case func.publicity, string.ends_with(func.name, "_test") {
        Public, True -> Ok(parse_function(func))
        _, _ -> Error(Nil)
      }
    })

  Ok(tests)
}

fn parse_function(func: Function) -> ParsedTest {
  let tags = extract_tags_from_body(func.body)
  ParsedTest(name: func.name, tags: list.unique(tags))
}

fn extract_tags_from_body(statements: List(Statement)) -> List(String) {
  list.flat_map(statements, extract_tags_from_statement)
}

fn extract_tags_from_statement(stmt: Statement) -> List(String) {
  case stmt {
    Use(function: func, ..) -> extract_tags_from_expr(func)
    ExprStatement(expr) -> extract_tags_from_expr(expr)
    _ -> []
  }
}

fn extract_tags_from_expr(expr: Expression) -> List(String) {
  case expr {
    // unitest.tag("slow")
    Call(
      function: FieldAccess(
        container: Variable(name: "unitest", ..),
        label: "tag",
        ..,
      ),
      arguments: args,
      ..,
    ) -> extract_single_tag(args)

    // unitest.tags(["slow", "db"])
    Call(
      function: FieldAccess(
        container: Variable(name: "unitest", ..),
        label: "tags",
        ..,
      ),
      arguments: args,
      ..,
    ) -> extract_tags_list(args)

    _ -> []
  }
}

fn extract_single_tag(args: List(glance.Field(Expression))) -> List(String) {
  case args {
    [UnlabelledField(StringExpr(value: tag, ..))] -> [tag]
    _ -> []
  }
}

fn extract_tags_list(args: List(glance.Field(Expression))) -> List(String) {
  case args {
    [UnlabelledField(ListExpr(elements: elements, ..))] ->
      list.filter_map(elements, fn(elem) {
        case elem {
          StringExpr(value: tag, ..) -> Ok(tag)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}
