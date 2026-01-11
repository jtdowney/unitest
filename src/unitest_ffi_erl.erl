-module(unitest_ffi_erl).
-export([run_test/1, auto_seed/0, now_ms/0]).

%% Run a test function and return Ok(Nil) or Error(Reason)
%% Test is a Gleam record: {test, Module, Name, Tags}
run_test({test, ModuleBin, NameBin, _Tags}) ->
    ModuleConverted = binary:replace(ModuleBin, <<"/">>, <<"@">>, [global]),
    Module = erlang:binary_to_atom(ModuleConverted, utf8),
    Name = erlang:binary_to_atom(NameBin, utf8),
    try
        Module:Name(),
        {ok, nil}
    catch
        error:Reason:Stack ->
            {error, format_error(Reason, Stack)};
        throw:Reason:Stack ->
            {error, format_error(Reason, Stack)};
        exit:Reason:Stack ->
            {error, format_error(Reason, Stack)}
    end.

format_error(Reason, Stack) ->
    Formatted = io_lib:format("~p~n~p", [Reason, Stack]),
    erlang:list_to_binary(lists:flatten(Formatted)).

%% Generate a random seed based on current time
auto_seed() ->
    erlang:system_time(millisecond) rem 1000000.

%% Get current time in milliseconds
now_ms() ->
    erlang:system_time(millisecond).
