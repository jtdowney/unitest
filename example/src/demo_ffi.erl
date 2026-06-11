-module(demo_ffi).

-export([crash/0]).

%% Raise a raw runtime error so unitest reports a Crashed failure
crash() ->
    erlang:error(simulated_crash).
