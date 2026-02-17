-module(unitest_guard_demo_ffi).
-export([otp_version/0]).

otp_version() ->
    list_to_integer(erlang:system_info(otp_release)).
