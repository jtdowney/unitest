import gleam/list
import gleam/time/duration
import unitest
import unitest/internal/discovery

pub fn pool_fixture_pass() -> Nil {
  Nil
}

pub fn pool_fixture_pass_two() -> Nil {
  Nil
}

@external(erlang, "unitest_ffi", "start_module_pool")
@external(javascript, "../unitest_ffi.mjs", "startModulePool")
fn real_start_module_pool(
  groups: List(List(discovery.Test)),
  package: String,
  check_results: Bool,
  timeout_ms: Int,
  workers: Int,
) -> Nil

@external(erlang, "unitest_ffi", "receive_pool_result")
@external(javascript, "../unitest_ffi.mjs", "receivePoolResult")
fn real_receive_pool_result(callback: fn(unitest.TestResult) -> Nil) -> Nil

@external(erlang, "unitest_test_ffi", "execute_sync_pooled")
@external(javascript, "../unitest_test_ffi.mjs", "executeSyncPooledJs")
fn execute_sync_pooled(
  plan: List(unitest.PlanItem),
  seed: Int,
  workers: Int,
  platform: unitest.Platform,
  on_result: fn(unitest.TestResult, unitest.Progress, fn() -> Nil) -> Nil,
  callback: fn(unitest.ExecuteResult) -> a,
) -> a

fn noop_on_result(
  _result: unitest.TestResult,
  _progress: unitest.Progress,
  continue: fn() -> Nil,
) -> Nil {
  continue()
}

fn fixture(name: String) -> discovery.Test {
  discovery.Test(
    module: "integration/pool_test",
    name:,
    tags: [],
    file_path: "test/integration/pool_test.gleam",
    line_span: discovery.LineSpan(1, 1000),
  )
}

fn real_platform() -> unitest.Platform {
  unitest.Platform(
    now_ms: fn() { 0 },
    run_test: fn(_t, k) { k(unitest.Passed) },
    start_module_pool: fn(groups, workers) {
      real_start_module_pool(groups, "unitest", False, 0, workers)
    },
    receive_pool_result: real_receive_pool_result,
  )
}

pub fn real_pool_produces_valid_durations_test() {
  let plan = [
    unitest.Run(fixture("pool_fixture_pass")),
    unitest.Run(fixture("pool_fixture_pass_two")),
  ]

  use exec_result <- execute_sync_pooled(
    plan,
    1,
    2,
    real_platform(),
    noop_on_result,
  )

  let results = exec_result.results
  assert list.length(results) == 2
  assert list.all(results, fn(result) {
    duration.to_milliseconds(result.duration) >= 0
  })
}
