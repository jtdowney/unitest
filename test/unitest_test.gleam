import unitest
import unitest/internal/runner.{Report}

pub fn main() -> Nil {
  unitest.main()
}

pub fn exit_code_zero_when_no_failures_test() {
  let report =
    Report(
      passed: 5,
      failed: 0,
      skipped: 1,
      failures: [],
      seed: 1,
      runtime_ms: 100,
    )
  assert unitest.exit_code(report) == 0
}

pub fn exit_code_one_when_failures_test() {
  let report =
    Report(
      passed: 4,
      failed: 1,
      skipped: 0,
      failures: [],
      seed: 1,
      runtime_ms: 100,
    )
  assert unitest.exit_code(report) == 1
}

pub fn exit_code_one_when_multiple_failures_test() {
  let report =
    Report(
      passed: 3,
      failed: 5,
      skipped: 0,
      failures: [],
      seed: 1,
      runtime_ms: 100,
    )
  assert unitest.exit_code(report) == 1
}
