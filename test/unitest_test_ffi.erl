-module(unitest_test_ffi).

-export([execute_sync/5]).

execute_sync(Plan, Seed, Platform, OnResult, Callback) ->
    Self = self(),
    unitest@internal@runner:execute(
        Plan,
        Seed,
        Platform,
        OnResult,
        fun(Result) -> Self ! {execute_result, Result} end
    ),
    receive
        {execute_result, Result} ->
            Callback(Result)
    end.
