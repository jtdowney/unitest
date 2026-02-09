# unitest

[![Package Version](https://img.shields.io/hexpm/v/unitest)](https://hex.pm/packages/unitest)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/unitest/)

A Gleam test runner with random ordering, tagging, and CLI filtering. It is a drop-in replacement for gleeunit if you're already using asserts.

## Installation

1.

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

- **Random test ordering** with reproducible seeds
- **Test tagging** for categorization and filtering
- **Runtime guards** for conditional test execution (platform, version checks)
- **CLI filtering** by file path, line number, test name, or tag
- **Parallel execution** of module groups with configurable worker count
- **Flexible output**: streaming dots (default) or table format

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
gleam test -- --test my_mod_test.fn           # Single test by name
gleam test -- --tag slow                      # Tests with tag
gleam test -- test/foo_test.gleam --tag slow  # Combine file + tag
gleam test -- --workers 4                     # Parallel with 4 module-group workers
```

The positional file argument supports partial matching, so `my_mod_test.gleam` will match `test/my_mod_test.gleam`.

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

Tests can return `Result(a, e)` instead of `Nil`. When `check_results: True` is enabled, returning `Error(reason)` is treated as a test failure:

```gleam
import unitest.{Options}

pub fn main() {
  unitest.run(Options(..unitest.default_options(), check_results: True))
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
import unitest.{Options}

pub fn main() {
  unitest.run(Options(..unitest.default_options(), ignored_tags: ["slow"]))
}
```

Tests tagged "slow" will show as `S` (skipped).
Override with `gleam test -- --tag slow`.

## Examples

See [`examples/demo/`](examples/demo/) for a complete working project.

Further documentation at [hexdocs.pm/unitest](https://hexdocs.pm/unitest).
