-module(unitest_test_ffi).

-export([
    execute_sync_sequential/5, execute_sync_pooled/6, send_pool_result/1, receive_pool_result_test/1
]).

execute_sync_sequential(Plan, Seed, Platform, OnResult, Callback) ->
    Self = self(),
    unitest@internal@runner:execute_sequential(
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

execute_sync_pooled(Plan, Seed, Workers, Platform, OnResult, Callback) ->
    Self = self(),
    unitest@internal@runner:execute_pooled(
        Plan,
        Seed,
        Workers,
        Platform,
        OnResult,
        fun(Result) -> Self ! {execute_result, Result} end
    ),
    receive
        {execute_result, Result} ->
            Callback(Result)
    end.

send_pool_result(PoolResult) ->
    self() ! {unitest_pool_result, PoolResult},
    nil.

receive_pool_result_test(Callback) ->
    receive
        {unitest_pool_result, PoolResult} ->
            Callback(PoolResult)
    end.
