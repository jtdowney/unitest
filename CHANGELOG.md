# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added

- Per-test timeouts: tests that exceed the timeout fail with
  `Test timed out after <n>ms` instead of hanging the run. Configure with
  `--timeout <ms>` (0 disables) or `unitest.timeout(duration)`; the default is
  60 seconds. On JavaScript, a synchronously hanging test can only be
  interrupted in parallel (worker thread) mode
- `unitest.table_reporter()` makes the table reporter the default; the
  `--reporter` CLI flag still overrides it
- Process crashes report the crash reason and a stack trace filtered to user
  code; calls to undefined functions are reported as `module:function/arity`
- File filters accept absolute paths and Windows-style separators
  (`C:\proj\test\my_mod_test.gleam:42`)

### Changed

- Breaking: `Options` is now opaque. Replace
  `Options(..unitest.default_options(), ...)` record updates with
  `unitest.defaults()` piped through builder functions: `seed`,
  `ignored_tags`, `check_results`, `execution_mode`, `sort_order`,
  `sort_reversed`, `table_reporter`, and `timeout`
- Breaking: `gleam_stdlib >= 0.50.0` is now required
- `SortOrder` (`NativeSort`, `TimeSort`, `NameSort`) is now part of the public
  `unitest` API for use with `unitest.sort_order`
- On JavaScript, parallel workers now pull individual tests from a shared
  queue instead of running whole module groups

### Removed

- Breaking: `default_options()` and the `test_directory` option; test
  discovery always scans `test/`

### Fixed

- Use singular "failure" in the summary line when exactly one test fails

## [1.6.0] - 2026-05-30

### Added

- Warn on stderr when a test file fails to parse, instead of silently skipping its tests
- Warn on stderr when no tests are discovered

### Fixed

- Resolve the package name only from an exact `name` key in `gleam.toml`, avoiding false matches on similarly named keys

## [1.5.0] - 2026-02-09

### Added

- Tests now run concurrently using module-group pooling for faster test suites
- Tests are shuffled by module group instead of individually, preserving intra-module ordering while randomizing across modules

### Fixed

- Validate non-empty segments in test filter parsing

## [1.4.3] - 2026-02-02

### Changed

- Simplified internal random seed generation using stdlib

## [1.4.2] - 2026-01-28

### Fixed

- Use lazy evaluation in `unitest.guard` to prevent skip conditions from being evaluated eagerly

## [1.4.1] - 2026-01-27

### Fixed

- Error result checking is now opt-in: the `check_results` option must be explicitly enabled to treat `Error` return values as test failures, preventing unexpected failures for codebases that intentionally return `Error` from tests

## [1.4.0] - 2026-01-26

### Added

- Use `unitest.guard(condition)` to skip tests at runtime based on environment or configuration
- Tests returning `Error` values are now treated as failures, making it easier to write tests that use result types

## [1.3.1] - 2026-01-18

### Fixed

- Sort skipped tests after 0ms tests in table reporter for consistent ordering

## [1.3.0] - 2026-01-18

### Added

- Configure table reporter output with `--sort time` (by duration) or `--sort name` (alphabetically), plus `--sort-rev` to reverse order
- Filter tests by `@target` attribute to run platform-specific tests

## [1.2.0] - 2026-01-17

### Added

- New `--reporter table` option for formatted test result output

## [1.1.0] - 2026-01-12

### Added

- Run all tests in a specific file with `gleam test -- test/my_mod_test.gleam`
- Run the test at a specific line with `gleam test -- test/my_mod_test.gleam:42`
- Better error messages when undefined functions are referenced

### Fixed

- Always halt the VM regardless of test exit code, ensuring proper cleanup (#1)

## [1.0.0] - 2026-01-11

Initial release of unitest, a Gleam test runner with random ordering, tagging, and CLI filtering.

### Added

- Drop-in gleeunit replacement: swap `gleeunit.main()` for `unitest.main()` for instant compatibility if you are using asserts
- Tests run in random order by default to catch hidden dependencies
- Use `--seed <int>` to reproduce exact test order for debugging flaky tests
- Mark tests with `unitest.tag("name")` or `unitest.tags(["a", "b"])` using `use` syntax
- CLI filtering:
  - `--module <name>`: Run only tests in a specific module
  - `--test <module.fn>`: Run a single test function
  - `--tag <name>`: Run only tests with a specific tag
- Configure `ignored_tags` in `Options` to skip tests by default (shown as `S`)
- Streaming output with real-time feedback: `.` (pass), `F` (fail), `S` (skip)
- Colored output by default, respecting the `NO_COLOR` environment variable and `--no-color` flag
- Works on Erlang and JavaScript targets

[1.6.0]: https://github.com/jtdowney/unitest/releases/tag/v1.6.0
[1.5.0]: https://github.com/jtdowney/unitest/releases/tag/v1.5.0
[1.4.3]: https://github.com/jtdowney/unitest/releases/tag/v1.4.3
[1.4.2]: https://github.com/jtdowney/unitest/releases/tag/v1.4.2
[1.4.1]: https://github.com/jtdowney/unitest/releases/tag/v1.4.1
[1.4.0]: https://github.com/jtdowney/unitest/releases/tag/v1.4.0
[1.3.1]: https://github.com/jtdowney/unitest/releases/tag/v1.3.1
[1.3.0]: https://github.com/jtdowney/unitest/releases/tag/v1.3.0
[1.2.0]: https://github.com/jtdowney/unitest/releases/tag/v1.2.0
[1.1.0]: https://github.com/jtdowney/unitest/releases/tag/v1.1.0
[1.0.0]: https://github.com/jtdowney/unitest/releases/tag/v1.0.0
