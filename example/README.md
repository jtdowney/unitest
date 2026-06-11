# Unitest Demo

This project demonstrates the features of unitest, a Gleam test runner with random ordering, tagging, and CLI filtering.

## Running Tests

```bash
# Run all tests (with random ordering)
gleam test

# Run with a specific seed for reproducible ordering
gleam test -- --seed 12345

# Run only tests in a specific file
gleam test -- demo_test.gleam

# Run a single test
gleam test -- --test tagged_test.fibonacci_small_test

# Run only tests with a specific tag
gleam test -- --tag slow
gleam test -- --tag integration
```

## Test Files

### `test/demo_test.gleam`

Basic unit tests demonstrating standard test discovery. Any public function ending in `_test` is automatically discovered and run.

### `test/tagged_test.gleam`

Demonstrates the tagging feature:

```gleam
// Single tag
pub fn slow_test() {
  use <- unitest.tag("slow")
  // ... slow test code
}

// Multiple tags
pub fn integration_slow_test() {
  use <- unitest.tags(["integration", "slow"])
  // ... test code
}
```

### `test/guard_test.gleam`

Demonstrates runtime guards for conditionally skipping tests:

```gleam
// Skip unless a condition holds at runtime
pub fn database_integration_test() {
  use <- require_env("DATABASE_URL")
  // ... test code
}

fn require_env(name: String, next: fn() -> a) -> a {
  unitest.guard(envoy.get(name) |> result.is_ok, next)
}
```

Guarded tests that don't run are reported as skipped (`S`).

### `test/wibble/wobble_test.gleam`

Shows that test discovery recurses into nested directories under `test/`.

## Features Demonstrated

- Public functions ending in `_test` are automatically discovered
- Tests run in random order by default; pass `--seed` for reproducible ordering
- Tests can be tagged with `unitest.tag()` or `unitest.tags()`
- Tests can be skipped at runtime with `unitest.guard()`
- Runs can be filtered by file path, `--test`, or `--tag`
- Output streams `.` for pass, `F` for fail, `S` for skip
