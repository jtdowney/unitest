-module(unitest_ffi).

-export([run_test/2, run_test_async/4, now_ms/0, skip/0]).

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

%% Throw a skip exception to signal guard-based test skip
skip() ->
    throw({gleam_unitest, skip}).

%% Run a test function and return ran, runtime_skip, or {run_error, TestFailure}
%% Test is a Gleam record: {test, Module, Name, Tags, FilePath, LineSpan}
%% CheckResults: when true, treat Error results as test failures
run_test({test, ModuleBin, NameBin, _Tags, _FilePath, _LineSpan}, CheckResults) ->
    ModuleConverted = binary:replace(ModuleBin, <<"/">>, <<"@">>, [global]),
    Module = erlang:binary_to_atom(ModuleConverted, utf8),
    Name = erlang:binary_to_atom(NameBin, utf8),
    try Module:Name() of
        {error, Reason} when CheckResults =:= true ->
            Message = iolist_to_binary([<<"Test returned Error: ">>, gleam@string:inspect(Reason)]),
            {run_error, #test_failure{
                message = Message,
                file = <<>>,
                module = <<>>,
                function = <<>>,
                line = 0,
                kind = generic
            }};
        _ ->
            ran
    catch
        throw:{gleam_unitest, skip} ->
            runtime_skip;
        error:Reason:Stack ->
            {run_error, parse_gleam_error(Reason, Stack)};
        throw:Reason:Stack ->
            {run_error, parse_gleam_error(Reason, Stack)};
        exit:Reason:Stack ->
            {run_error, parse_gleam_error(Reason, Stack)}
    end.

run_test_async(Test, _PackageName, CheckResults, Continuation) ->
    Result = run_test(Test, CheckResults),
    Continuation(Result).

%% Parse Gleam error maps into GleamPanic records
parse_gleam_error(Reason, _Stack) when is_map(Reason) ->
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
            build_generic_panic(Reason, [])
    end;
parse_gleam_error(undef, Stack) ->
    build_undef_panic(Stack);
parse_gleam_error(Reason, Stack) ->
    build_generic_panic(Reason, Stack).

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

%% Build panic for undefined function errors
build_undef_panic([{M, F, A, _Info} | _Rest]) ->
    Arity =
        case A of
            Args when is_list(Args) ->
                length(Args);
            N when is_integer(N) ->
                N
        end,
    Message = iolist_to_binary(io_lib:format("Undefined function: ~s:~s/~B", [M, F, Arity])),
    #test_failure{
        message = Message,
        file = <<>>,
        module = <<>>,
        function = <<>>,
        line = 0,
        kind = generic
    };
build_undef_panic(_) ->
    #test_failure{
        message = <<"Undefined function">>,
        file = <<>>,
        module = <<>>,
        function = <<>>,
        line = 0,
        kind = generic
    }.

%% Build panic for generic/unknown errors
build_generic_panic(Reason, Stack) ->
    StackInfo = format_stack_summary(Stack),
    BaseMessage = iolist_to_binary(io_lib:format("~p", [Reason])),
    Message =
        case StackInfo of
            <<>> ->
                BaseMessage;
            _ ->
                <<BaseMessage/binary, "\n", StackInfo/binary>>
        end,
    #test_failure{
        message = Message,
        file = <<>>,
        module = <<>>,
        function = <<>>,
        line = 0,
        kind = generic
    }.

%% Format a brief stack summary (first meaningful frame)
format_stack_summary([{M, F, A, Info} | _]) ->
    Arity =
        case A of
            Args when is_list(Args) ->
                length(Args);
            N when is_integer(N) ->
                N
        end,
    case proplists:get_value(file, Info) of
        undefined ->
            iolist_to_binary(io_lib:format("  in ~s:~s/~B", [M, F, Arity]));
        File ->
            Line = proplists:get_value(line, Info, 0),
            iolist_to_binary(io_lib:format("  in ~s:~s/~B (~s:~B)", [M, F, Arity, File, Line]))
    end;
format_stack_summary(_) ->
    <<>>.

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

%% Get current time in milliseconds
now_ms() ->
    erlang:system_time(millisecond).
