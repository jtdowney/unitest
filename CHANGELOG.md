# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-01-18

### Added

- **Table sorting**: Configure table reporter output with `--sort time` (by duration) or `--sort name` (alphabetically), plus `--sort-rev` to reverse order
- **Target filtering**: Filter tests by `@target` attribute to run platform-specific tests

## [1.2.0] - 2026-01-17

### Added

- **Table reporter**: New `--reporter table` option for formatted test result output

## [1.1.0] - 2026-01-12

### Added

- **File path filtering**: Run tests in a specific file with `gleam test -- test/my_mod_test.gleam`
- **Line number filtering**: Run the test at a specific line with `gleam test -- test/my_mod_test.gleam:42`
- **Improved error messages**: Better context when undefined functions are referenced

### Fixed

- Always halt the VM regardless of test exit code, ensuring proper cleanup (#1)

## [1.0.0] - 2026-01-11

Initial release of unitest, a Gleam test runner with random ordering, tagging, and CLI filtering.

### Added

- **Drop-in gleeunit replacement**: Replace `gleeunit.main()` with `unitest.main()` for instant compatibility if you are using asserts
- **Random test ordering**: Tests run in random order by default to catch hidden dependencies
- **Reproducible seeds**: Use `--seed <int>` to reproduce exact test order for debugging flaky tests
- **Test tagging**: Mark tests with `unitest.tag("name")` or `unitest.tags(["a", "b"])` using `use` syntax
- **CLI filtering**:
  - `--module <name>`: Run only tests in a specific module
  - `--test <module.fn>`: Run a single test function
  - `--tag <name>`: Run only tests with a specific tag
- **Ignored tags**: Configure `ignored_tags` in `Options` to skip tests by default (shown as `S`)
- **Streaming output**: Real-time feedback with `.` (pass), `F` (fail), `S` (skip)
- **Color output**: Colored output by default, respects `NO_COLOR` environment variable and `--no-color` flag
- **Cross-platform support**: Works on Erlang and JavaScript targets

[1.3.0]: https://github.com/jtdowney/unitest/releases/tag/v1.3.0
[1.2.0]: https://github.com/jtdowney/unitest/releases/tag/v1.2.0
[1.1.0]: https://github.com/jtdowney/unitest/releases/tag/v1.1.0
[1.0.0]: https://github.com/jtdowney/unitest/releases/tag/v1.0.0
