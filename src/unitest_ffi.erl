-module(unitest_ffi).

-export([run_test/1, auto_seed/0, now_ms/0]).

-include_lib("unitest/include/unitest@internal@test_failure_TestFailure.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Assert.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_LetAssert.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_BinaryOperator.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_FunctionCall.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_OtherExpression.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_AssertedExpr.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Literal.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Expression.hrl").

get_file(Map) ->
    maps:get(file, Map, <<"">>).

get_module(Map) ->
    maps:get(module, Map, <<"">>).

get_function(Map) ->
    maps:get(function, Map, <<"">>).

get_line(Map) ->
    maps:get(line, Map, 0).

get_start(Map) ->
    maps:get(start, Map, 0).

get_end(Map) ->
    maps:get('end', Map, 0).

%% Run a test function and return Ok(Nil) or Error(GleamPanic)
%% Test is a Gleam record: {test, Module, Name, Tags, FilePath, LineSpan}
run_test({test, ModuleBin, NameBin, _Tags, _FilePath, _LineSpan}) ->
    ModuleConverted = binary:replace(ModuleBin, <<"/">>, <<"@">>, [global]),
    Module = erlang:binary_to_atom(ModuleConverted, utf8),
    Name = erlang:binary_to_atom(NameBin, utf8),
    try
        Module:Name(),
        {ok, nil}
    catch
        error:Reason:_Stack ->
            {error, parse_gleam_error(Reason)};
        throw:Reason:_Stack ->
            {error, parse_gleam_error(Reason)};
        exit:Reason:_Stack ->
            {error, parse_gleam_error(Reason)}
    end.

%% Parse Gleam error maps into GleamPanic records
parse_gleam_error(Reason) when is_map(Reason) ->
    case maps:get(gleam_error, Reason, undefined) of
        assert ->
            build_assert_panic(Reason);
        panic ->
            build_simple_panic(Reason, panic);
        todo ->
            build_simple_panic(Reason, todo);
        let_assert ->
            build_let_assert_panic(Reason);
        _ ->
            build_generic_panic(Reason)
    end;
parse_gleam_error(Reason) ->
    build_generic_panic(Reason).

build_assert_panic(Map) ->
    #test_failure{
        message = maps:get(message, Map, <<"Assertion failed">>),
        file = get_file(Map),
        module = get_module(Map),
        function = get_function(Map),
        line = get_line(Map),
        kind =
            #assert{
                start = get_start(Map),
                'end' = get_end(Map),
                expression_start = maps:get(expression_start, Map, 0),
                kind = build_assert_kind(Map)
            }
    }.

build_let_assert_panic(Map) ->
    Value = maps:get(value, Map, undefined),
    #test_failure{
        message = maps:get(message, Map, <<"Let assert failed">>),
        file = get_file(Map),
        module = get_module(Map),
        function = get_function(Map),
        line = get_line(Map),
        kind =
            #let_assert{
                start = get_start(Map),
                'end' = get_end(Map),
                value = gleam@string:inspect(Value)
            }
    }.

build_simple_panic(Map, Kind) ->
    #test_failure{
        message = maps:get(message, Map, <<"Panic">>),
        file = get_file(Map),
        module = get_module(Map),
        function = get_function(Map),
        line = get_line(Map),
        kind = Kind
    }.

%% Build panic for generic/unknown errors
build_generic_panic(Reason) ->
    Message = iolist_to_binary(io_lib:format("~p", [Reason])),
    #test_failure{
        message = Message,
        file = <<>>,
        module = <<>>,
        function = <<>>,
        line = 0,
        kind = generic
    }.

%% Build AssertKind based on the 'kind' field in the error map
build_assert_kind(Map) ->
    case maps:get(kind, Map, undefined) of
        binary_operator ->
            #binary_operator{
                operator = atom_to_binary(maps:get(operator, Map, '=='), utf8),
                left = build_asserted_expr(maps:get(left, Map, #{})),
                right = build_asserted_expr(maps:get(right, Map, #{}))
            };
        function_call ->
            Args = maps:get(arguments, Map, []),
            #function_call{arguments = [build_asserted_expr(A) || A <- Args]};
        other_expression ->
            #other_expression{expression = build_asserted_expr(maps:get(expression, Map, #{}))};
        _ ->
            %% Fallback: treat as other_expression with unevaluated
            #other_expression{
                expression =
                    #asserted_expr{
                        start = 0,
                        'end' = 0,
                        kind = unevaluated
                    }
            }
    end.

build_asserted_expr(Map) when is_map(Map) ->
    #asserted_expr{
        start = get_start(Map),
        'end' = get_end(Map),
        kind = build_expr_kind(Map)
    };
build_asserted_expr(_) ->
    #asserted_expr{
        start = 0,
        'end' = 0,
        kind = unevaluated
    }.

%% Build ExprKind from a map
build_expr_kind(Map) ->
    case maps:get(kind, Map, undefined) of
        literal ->
            Value = maps:get(value, Map, undefined),
            #literal{value = gleam@string:inspect(Value)};
        expression ->
            Value = maps:get(value, Map, undefined),
            #expression{value = gleam@string:inspect(Value)};
        _ ->
            unevaluated
    end.

%% Generate a random seed based on current time
auto_seed() ->
    erlang:system_time(millisecond) rem 1000000.

%% Get current time in milliseconds
now_ms() ->
    erlang:system_time(millisecond).
