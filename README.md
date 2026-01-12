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
- **CLI filtering** by module, test name, or tag
- **Streaming output**: `.` pass, `F` fail, `S` skip

## Future Work?

- Parallel execution
- Wildcard filtering
- Smarter tag discovery

## CLI Usage

```bash
gleam test                            # Random order
gleam test -- --seed 123              # Reproducible order
gleam test -- --module my_mod_test    # Single module
gleam test -- --test my_mod_test.fn   # Single test
gleam test -- --tag slow              # Tests with tag
```

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
