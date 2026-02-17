//// Tests demonstrating unitest's guard feature for runtime test skipping.
////
//// Run with:
////   gleam test                     # skipped tests show as S
////   gleam test -- guard_test.gleam # run only guard demos

import demo
import envoy
import unitest

@external(erlang, "unitest_guard_demo_ffi", "otp_version")
fn otp_version() -> Int {
  0
}

fn require_otp(min_version: Int, next: fn() -> a) -> a {
  unitest.guard(otp_version() >= min_version, next)
}

fn require_env(name: String, next: fn() -> a) -> a {
  unitest.guard(envoy.get(name) |> result_is_ok, next)
}

fn result_is_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn guard_always_runs_test() {
  use <- unitest.guard(True)
  assert demo.add(1, 1) == 2
}

pub fn guard_always_skipped_test() {
  use <- unitest.guard(False)
  panic as "this should never run"
}

pub fn otp26_features_test() {
  use <- require_otp(26)
  assert demo.multiply(6, 7) == 42
}

pub fn future_otp_test() {
  use <- require_otp(99)
  panic as "this should never run until OTP 99"
}

pub fn database_integration_test() {
  use <- require_env("DATABASE_URL")
  assert demo.divide(100, 10) == Ok(10)
}

pub fn ci_only_test() {
  use <- require_env("CI")
  assert demo.add(1, 1) == 2
}

pub fn chained_guards_test() {
  use <- unitest.guard(True)
  use <- unitest.guard(demo.is_even(4))
  assert demo.add(2, 2) == 4
}

pub fn first_guard_fails_test() {
  use <- unitest.guard(False)
  use <- unitest.guard(True)
  panic as "this should never run"
}

pub fn second_guard_fails_test() {
  use <- unitest.guard(True)
  use <- unitest.guard(False)
  panic as "this should never run"
}

pub fn tagged_and_guarded_test() {
  use <- unitest.tag("integration")
  use <- unitest.guard(True)
  assert demo.divide(10, 2) == Ok(5)
}
