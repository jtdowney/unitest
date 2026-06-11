-module(unitest_ffi).

-export([
    run_test_async/5,
    now_ms/0,
    skip/0,
    default_workers/0,
    start_module_pool/5,
    receive_pool_result/1
]).

-include_lib("unitest/include/unitest@internal@discovery_Test.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_TestFailure.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Assert.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_LetAssert.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_BinaryOperator.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_FunctionCall.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_OtherExpression.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_AssertedExpr.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Literal.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Expression.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Crashed.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_StackFrame.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Timeout.hrl").
-include_lib("unitest/include/unitest@internal@test_failure_Undef.hrl").

%% The remaining Gleam types these values mirror (TestResult, Outcome) are
%% @internal, so Gleam emits no record .hrl for them. The FFI builds those
%% tuples directly: the tag is the constructor in snake_case and the elements
%% follow the Gleam field declaration order (see the type definitions in
%% src/unitest.gleam). Nullary constructors are bare atoms (passed, skipped,
%% generic, unevaluated...). #pool and #worker below are the FFI's own state,
%% not Gleam types.
-record(pool, {queue, limit, in_flight, workers, parent, check_results, timeout_ms}).
-record(worker, {
    remaining, max_concurrent, in_flight, pid_map, manager, check_results, timeout_ms
}).

%% Throw a skip exception to signal guard-based test skip
skip() ->
    throw({gleam_unitest, skip}).

%% Run a test function and return passed, skipped, or {failed, TestFailure}
run_test(#test{module = ModuleBin, name = NameBin}, CheckResults) ->
    ModuleConverted = binary:replace(ModuleBin, <<"/">>, <<"@">>, [global]),
    Module = erlang:binary_to_atom(ModuleConverted, utf8),
    Name = erlang:binary_to_atom(NameBin, utf8),
    try Module:Name() of
        {error, Reason} when CheckResults =:= true ->
            Message = iolist_to_binary([<<"Test returned Error: ">>, gleam@string:inspect(Reason)]),
            {failed, generic_failure(Message)};
        _ ->
            passed
    catch
        {gleam_unitest, skip} ->
            skipped;
        error:Reason:Stack ->
            {failed, parse_gleam_error(Reason, Stack)};
        throw:Reason:Stack ->
            {failed, parse_gleam_error(Reason, Stack)};
        exit:Reason:Stack ->
            {failed, parse_gleam_error(Reason, Stack)}
    end.

run_test_async(Test, _PackageName, CheckResults, TimeoutMs, Continuation) ->
    Result = run_test_with_timeout(Test, CheckResults, TimeoutMs),
    Continuation(Result).

run_test_with_timeout(Test, CheckResults, TimeoutMs) ->
    Parent = self(),
    %% A non-positive timeout means "disabled", matching the JavaScript FFI.
    EffectiveTimeout =
        case TimeoutMs of
            N when N =< 0 ->
                infinity;
            N ->
                N
        end,
    {Pid, Ref} =
        spawn_monitor(fun() -> Parent ! {test_outcome, self(), run_test(Test, CheckResults)} end),
    receive
        {test_outcome, Pid, Outcome} ->
            erlang:demonitor(Ref, [flush]),
            Outcome;
        {'DOWN', Ref, process, Pid, Reason} ->
            {failed, crashed_failure(Reason, [])}
    after EffectiveTimeout ->
        exit(Pid, kill),
        %% Await the DOWN so any test_outcome the test sent before dying is
        %% already queued (signal ordering), then drop it from the mailbox.
        receive
            {'DOWN', Ref, process, Pid, _} -> ok
        end,
        flush_test_outcome(Pid),
        {failed, #test_failure{
            message = <<"">>,
            file = <<"">>,
            line = 0,
            kind = #timeout{timeout_ms = TimeoutMs}
        }}
    end.

flush_test_outcome(Pid) ->
    receive
        {test_outcome, Pid, _} -> ok
    after 0 -> ok
    end.

inspect_term(Term) ->
    iolist_to_binary(io_lib:format("~p", [Term])).

%% Parse a Gleam panic/crash into a TestFailure tuple.
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
            crashed_failure(Reason, [])
    end;
parse_gleam_error(undef, Stack) ->
    build_undef_panic(Stack);
parse_gleam_error(Reason, Stack) ->
    crashed_failure(Reason, build_stack(Stack)).

base_failure(Map, DefaultMessage, Kind) ->
    #test_failure{
        message = maps:get(message, Map, DefaultMessage),
        file = maps:get(file, Map, <<"">>),
        line = maps:get(line, Map, 0),
        kind = Kind
    }.

generic_failure(Message) ->
    base_failure(#{}, Message, generic).

crashed_failure(Reason, Stack) ->
    #test_failure{
        message = <<"">>,
        file = <<"">>,
        line = 0,
        kind = #crashed{reason = inspect_term(Reason), stack = Stack}
    }.

build_assert_panic(Map) ->
    Kind =
        #assert{
            start = maps:get(start, Map, 0),
            'end' = maps:get('end', Map, 0),
            kind = build_assert_kind(Map)
        },
    base_failure(Map, <<"Assertion failed">>, Kind).

build_let_assert_panic(Map) ->
    Value = maps:get(value, Map, undefined),
    Kind =
        #let_assert{
            start = maps:get(start, Map, 0),
            'end' = maps:get('end', Map, 0),
            value = gleam@string:inspect(Value)
        },
    base_failure(Map, <<"Let assert failed">>, Kind).

build_simple_panic(Map, Kind) ->
    base_failure(Map, <<"Panic">>, Kind).

%% Build a TestFailure for undefined function errors.
build_undef_panic([{M, F, A, _Info} | _Rest]) ->
    #test_failure{
        message = <<"">>,
        file = <<"">>,
        line = 0,
        kind =
            #undef{
                module = atom_to_binary(M, utf8),
                function = atom_to_binary(F, utf8),
                arity = frame_arity(A)
            }
    };
build_undef_panic(_) ->
    generic_failure(<<"Undefined function">>).

%% Convert an Erlang stacktrace into stack frames.
build_stack(Stack) when is_list(Stack) ->
    [build_frame(Entry) || Entry <- Stack];
build_stack(_) ->
    [].

build_frame({M, F, A, Info}) ->
    #stack_frame{
        module = atom_to_binary(M, utf8),
        function = atom_to_binary(F, utf8),
        arity = frame_arity(A),
        file = frame_file(Info),
        line = proplists:get_value(line, Info, 0)
    }.

frame_arity(Args) when is_list(Args) ->
    length(Args);
frame_arity(N) when is_integer(N) ->
    N.

frame_file(Info) ->
    case proplists:get_value(file, Info) of
        undefined ->
            <<>>;
        File ->
            iolist_to_binary(File)
    end.

%% Build the AssertKind value from the 'kind' field in the error map.
build_assert_kind(Map) ->
    case maps:get(kind, Map, undefined) of
        binary_operator ->
            #binary_operator{
                operator = atom_to_binary(maps:get(operator, Map, '=='), utf8),
                left = build_asserted_expr(maps:get(left, Map, #{})),
                right = build_asserted_expr(maps:get(right, Map, #{}))
            };
        function_call ->
            #function_call{
                arguments = [build_asserted_expr(A) || A <- maps:get(arguments, Map, [])]
            };
        other_expression ->
            #other_expression{expression = build_asserted_expr(maps:get(expression, Map, #{}))};
        _ ->
            #other_expression{expression = #asserted_expr{start = 0, 'end' = 0, kind = unevaluated}}
    end.

build_asserted_expr(Map) when is_map(Map) ->
    #asserted_expr{
        start = maps:get(start, Map, 0),
        'end' = maps:get('end', Map, 0),
        kind = build_expr_kind(Map)
    };
build_asserted_expr(_) ->
    #asserted_expr{start = 0, 'end' = 0, kind = unevaluated}.

build_expr_kind(Map) ->
    case {maps:get(kind, Map, undefined), maps:find(value, Map)} of
        {literal, {ok, Value}} ->
            #literal{value = gleam@string:inspect(Value)};
        {expression, {ok, Value}} ->
            #expression{value = gleam@string:inspect(Value)};
        _ ->
            unevaluated
    end.

default_workers() ->
    erlang:system_info(schedulers_online).

start_module_pool(ModuleGroups, _PackageName, CheckResults, TimeoutMs, Workers) ->
    Pool =
        #pool{
            queue = queue:from_list(ModuleGroups),
            limit = max(1, Workers),
            in_flight = 0,
            workers = #{},
            parent = self(),
            check_results = CheckResults,
            timeout_ms = TimeoutMs
        },
    spawn_link(fun() -> pool_manager(Pool) end),
    nil.

pool_manager(
    #pool{
        queue = Queue,
        in_flight = InFlight,
        limit = Limit
    } =
        Pool
) ->
    case queue:is_empty(Queue) andalso InFlight =:= 0 of
        true ->
            ok;
        false ->
            case InFlight < Limit andalso not queue:is_empty(Queue) of
                true ->
                    dispatch_worker(Pool);
                false ->
                    await_worker(Pool)
            end
    end.

dispatch_worker(
    #pool{
        queue = Queue,
        in_flight = InFlight,
        workers = Workers
    } =
        Pool
) ->
    {{value, ModuleGroup}, Rest} = queue:out(Queue),
    Pid = spawn_module_worker(
        ModuleGroup,
        Pool#pool.check_results,
        Pool#pool.timeout_ms,
        self()
    ),
    pool_manager(Pool#pool{
        queue = Rest,
        in_flight = InFlight + 1,
        workers = maps:put(Pid, ModuleGroup, Workers)
    }).

await_worker(
    #pool{
        workers = Workers,
        parent = Parent,
        in_flight = InFlight
    } =
        Pool
) ->
    receive
        {pool_result, Pid, PoolResult} ->
            Parent ! {unitest_pool_result, PoolResult},
            pool_manager(Pool#pool{
                workers =
                    remove_pending_test(
                        Pid,
                        element(2, PoolResult),
                        Workers
                    )
            });
        {module_done, Pid} ->
            pool_manager(Pool#pool{in_flight = InFlight - 1, workers = maps:remove(Pid, Workers)});
        {'DOWN', _Ref, process, Pid, Reason} ->
            handle_worker_down(Pid, Reason, Pool)
    end.

handle_worker_down(
    Pid,
    Reason,
    #pool{
        workers = Workers,
        parent = Parent,
        in_flight = InFlight
    } =
        Pool
) ->
    case maps:find(Pid, Workers) of
        {ok, Pending} ->
            lists:foreach(
                fun(Test) ->
                    Parent ! {unitest_pool_result, build_crash_pool_result(Test, Reason)}
                end,
                Pending
            ),
            pool_manager(Pool#pool{in_flight = InFlight - 1, workers = maps:remove(Pid, Workers)});
        error ->
            pool_manager(Pool)
    end.

remove_pending_test(Pid, Test, Workers) ->
    case maps:find(Pid, Workers) of
        {ok, Pending} ->
            maps:put(Pid, lists:delete(Test, Pending), Workers);
        error ->
            Workers
    end.

spawn_module_worker(Tests, CheckResults, TimeoutMs, Manager) ->
    Worker =
        #worker{
            remaining = Tests,
            max_concurrent = max(1, erlang:system_info(schedulers_online)),
            in_flight = 0,
            pid_map = #{},
            manager = Manager,
            check_results = CheckResults,
            timeout_ms = TimeoutMs
        },
    {Pid, _Ref} =
        spawn_monitor(fun() ->
            process_flag(trap_exit, true),
            module_worker_loop(Worker)
        end),
    Pid.

module_worker_loop(#worker{
    remaining = [],
    in_flight = 0,
    manager = Manager
}) ->
    Manager ! {module_done, self()},
    ok;
module_worker_loop(
    #worker{
        remaining = Remaining,
        max_concurrent = MaxConcurrent,
        in_flight = InFlight
    } =
        Worker
) ->
    case InFlight < MaxConcurrent andalso Remaining =/= [] of
        true ->
            dispatch_test(Worker);
        false ->
            await_test(Worker)
    end.

dispatch_test(
    #worker{
        remaining = [Test | Rest],
        in_flight = InFlight,
        pid_map = PidMap
    } =
        Worker
) ->
    Self = self(),
    ChildPid =
        spawn_link(fun() ->
            Start = now_ms(),
            Result =
                run_test_with_timeout(
                    Test,
                    Worker#worker.check_results,
                    Worker#worker.timeout_ms
                ),
            Duration = now_ms() - Start,
            Self !
                {test_done, self(),
                    {test_result, Test, Result, gleam@time@duration:milliseconds(Duration)}}
        end),
    module_worker_loop(Worker#worker{
        remaining = Rest,
        in_flight = InFlight + 1,
        pid_map = maps:put(ChildPid, Test, PidMap)
    }).

await_test(
    #worker{
        in_flight = InFlight,
        pid_map = PidMap,
        manager = Manager
    } =
        Worker
) ->
    receive
        {test_done, ChildPid, PoolResult} ->
            Manager ! {pool_result, self(), PoolResult},
            module_worker_loop(Worker#worker{
                in_flight = InFlight - 1,
                pid_map = maps:remove(ChildPid, PidMap)
            });
        {'EXIT', ChildPid, Reason} ->
            handle_test_exit(ChildPid, Reason, Worker)
    end.

handle_test_exit(
    ChildPid,
    Reason,
    #worker{
        in_flight = InFlight,
        pid_map = PidMap,
        manager = Manager
    } =
        Worker
) ->
    case maps:find(ChildPid, PidMap) of
        {ok, Test} ->
            Manager ! {pool_result, self(), build_crash_pool_result(Test, Reason)},
            module_worker_loop(Worker#worker{
                in_flight = InFlight - 1,
                pid_map = maps:remove(ChildPid, PidMap)
            });
        error ->
            module_worker_loop(Worker)
    end.

build_crash_pool_result(Test, Reason) ->
    {test_result, Test, {failed, crashed_failure(Reason, [])}, gleam@time@duration:milliseconds(0)}.

receive_pool_result(Callback) ->
    receive
        {unitest_pool_result, PoolResult} ->
            Callback(PoolResult)
    end.

now_ms() ->
    erlang:monotonic_time(millisecond).
