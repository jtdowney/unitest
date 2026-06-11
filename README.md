# unitest

[![Package Version](https://img.shields.io/hexpm/v/unitest)](https://hex.pm/packages/unitest)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/unitest/)

A Gleam test runner with random ordering, tagging, and CLI filtering. It is a drop-in replacement for gleeunit if you're already using asserts.

## Installation

1. Swap gleeunit for unitest:

   ```sh
   gleam remove gleeunit
   gleam add unitest --dev
   gleam clean
   ```

2. Open `test/project_test.gleam` and replace `import gleeunit` with `import unitest` and `gleeunit.main()` with `unitest.main()`.

## Quick Start

Create `test/yourapp_test.gleam`:

```gleam
import unitest

pub fn main() {
  unitest.main()
}

pub fn addition_test() {
  assert 1 + 1 == 2
}
```

Run with `gleam test`.

## Features

- Random test ordering with reproducible seeds
- Test tagging for categorization and filtering
- Runtime guards for conditional test execution (platform, version checks)
- CLI filtering by file path, line number, test name, or tag
- Parallel test execution with configurable worker count
- Streaming dot (default) or table output format

## Why you may not want to use unitest

- It pulls in a lot of extra dependencies to offer the features above.

## Future Work?

- Wildcard filtering
- Smarter tag discovery

## CLI Usage

```bash
gleam test                                    # Random order
gleam test -- --seed 123                      # Reproducible order
gleam test -- --reporter table                # Table format output
gleam test -- --reporter table --sort time    # Table sorted by duration (slowest first)
gleam test -- --reporter table --sort name    # Table sorted alphabetically
gleam test -- --reporter table --sort time --sort-rev  # Table sorted fastest first
gleam test -- test/my_mod_test.gleam          # All tests in file
gleam test -- test/my_mod_test.gleam:42       # Test at line 42
gleam test -- --test my_mod_test.add_test     # Single test by name
gleam test -- --tag slow                      # Tests with tag
gleam test -- test/foo_test.gleam --tag slow  # Combine file + tag
gleam test -- --workers 4                     # Parallel with 4 workers
gleam test -- --timeout 30000                 # Per-test timeout in milliseconds (0 disables)
```

The `test/` prefix can be omitted from file paths: `my_mod_test.gleam` will match `test/my_mod_test.gleam`. Absolute paths and Windows-style separators (`C:\proj\test\my_mod_test.gleam:42`) also work.

> [!NOTE]
> **Timeouts on the JavaScript target.** A test that _synchronously_ hangs (an
> infinite loop with no `await`) can only be interrupted in the parallel mode,
> which runs tests in worker threads. The sequential and async modes run on
> the main thread, where a synchronous hang blocks the event loop and the
> timeout cannot fire.

## Table Reporter by Default

Make the table reporter the default so you don't need `--reporter table` on every run:

```gleam
import unitest

pub fn main() {
  unitest.defaults()
  |> unitest.table_reporter
  |> unitest.run
}
```

The `--reporter` CLI flag still overrides this.

## Tagging Tests

Mark tests for selective execution:

```gleam
import unitest

pub fn slow_test() {
  use <- unitest.tag("slow")
  // slow test code
}

pub fn integration_db_test() {
  use <- unitest.tags(["integration", "database"])
  // integration test code
}
```

## Error Results (Opt-In)

Tests can return `Result(a, e)` instead of `Nil`. When enabled via `unitest.check_results(True)`, returning `Error(reason)` is treated as a test failure:

```gleam
import unitest

pub fn main() {
  unitest.defaults()
  |> unitest.check_results(True)
  |> unitest.run
}

pub fn validation_test() -> Result(Nil, String) {
  case validate_config() {
    Ok(_) -> Ok(Nil)
    Error(msg) -> Error(msg)
  }
}
```

This is useful for tests that naturally work with `Result` types, avoiding the need for `let assert Ok(_) = ...` patterns.

## Runtime Guards

Skip tests at runtime based on conditions that can't be checked at compile time:

```gleam
import unitest

pub fn otp27_feature_test() {
  use <- unitest.guard(otp_version() >= 27)
  // test runs only if OTP >= 27
}

pub fn requires_database_test() {
  use <- unitest.guard(envoy.get("DATABASE_URL") |> result.is_ok)
  // test runs only if DATABASE_URL is set
}
```

Guards and tags can be combined:

```gleam
pub fn slow_integration_test() {
  use <- unitest.tag("slow")
  use <- unitest.guard(envoy.get("CI") |> result.is_ok)
  // slow test that only runs in CI
}
```

Skipped tests show as `S` in the output.

## Ignoring Tags by Default

Skip certain tags unless explicitly requested:

```gleam
import unitest

pub fn main() {
  unitest.defaults()
  |> unitest.ignored_tags(["slow"])
  |> unitest.run
}
```

Tests tagged "slow" will show as `S` (skipped).
Override with `gleam test -- --tag slow`.
