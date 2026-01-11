# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Unitest is a Gleam test runner library intended as a drop-in replacement for gleeunit with additional features: random test ordering (with reproducible seeds), test tagging, and CLI filtering by module/test/tag.

## Commands

```bash
gleam test                     # Run tests (Erlang target)
gleam test --target javascript --runtime node    # JS/Node target
gleam test --target javascript --runtime deno -- --allow-read=.,build,test,gleam.toml,manifest.toml  # JS/Deno target
gleam format --check src test  # Check formatting
gleam format src test          # Auto-format
gleam add <package>            # Add dependency (gets latest version)
```

### CLI Flags (passed after `--`)

```bash
gleam test -- --seed 123           # Reproducible ordering
gleam test -- --test my/mod.fn_test   # Run single test
gleam test -- --module my/mod_test    # Run single module
gleam test -- --tag slow              # Run tests with tag
```

## Architecture

### Planned Structure (per plan.md)

**Public API** (`src/unitest.gleam`):

- `main()` - gleeunit-compatible entry point
- `run(Options)` - configurable entry point
- `tag(String, fn() -> a)` / `tags(List(String), fn() -> a)` - test tagging via `use` syntax

**Internal Modules** (`src/unitest/internal/`):

- `cli.gleam` - argv parsing → structured CLI options
- `model.gleam` - types: Test, Filter, PlanItem, Outcome, Report
- `parse.gleam` - extract test functions + tags from Gleam source (static analysis)
- `select.gleam` - filter precedence: `--test` > `--module` > `--tag` > `ignored_tags`
- `rng.gleam` - deterministic PRNG + shuffle
- `run.gleam` - orchestration: discover → select → shuffle → execute → report
- `format_dot.gleam` - streaming `.`/`F`/`S` output + summary
- `discover.gleam` - filesystem adapter (simplifile)

**Platform FFI**:

- `platform_erl.gleam` + `unitest_ffi_erl.erl` - Erlang: exit codes, exception catching
- `platform_js.gleam` + `unitest_ffi_js.mjs` - JS: exit codes, module loading, exception catching

### Key Design Decisions

- Tags must be literal strings in `unitest.tag("literal")` or `unitest.tags(["a", "b"])` - non-literals cause parse errors
- Only `ignored_tags` produces `S` (skipped); filter exclusions are not counted/reported
- Tests sorted deterministically before shuffle to eliminate filesystem ordering leakage
- Pure functions tested in isolation; platform adapters inject dependencies for testability
