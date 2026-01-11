# Unitest Demo

This project demonstrates the features of unitest, a Gleam test runner with random ordering, tagging, and CLI filtering.

## Running Tests

```bash
# Run all tests (with random ordering)
gleam test

# Run with a specific seed for reproducible ordering
gleam test -- --seed 12345

# Run only tests in a specific module
gleam test -- --module demo_test

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

## Features Demonstrated

1. **Test Discovery** - Public functions ending in `_test` are automatically found
2. **Random Ordering** - Tests run in random order by default
3. **Reproducible Seeds** - Use `--seed` for deterministic ordering
4. **Test Tagging** - Mark tests with `unitest.tag()` or `unitest.tags()`
5. **CLI Filtering** - Filter by `--module`, `--test`, or `--tag`
6. **Dot Output** - Streaming `.` for pass, `F` for fail, `S` for skip
