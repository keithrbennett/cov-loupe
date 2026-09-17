# Demo project fixture

[Back to docs index](../../index.md)

This small demo project powers the documentation examples that rely on partial coverage and tracked globs.

- Location: `docs/fixtures/demo_project`
- Coverage file: `coverage/coverage.json` in this directory
- Suggested alias for docs: `alias clp='cov-loupe -R docs/fixtures/demo_project'`
- This fixture is static coverage reference material, not a project with its own test suite, but
  it is runnable with cov-loupe. Its `coverage.json` carries a deliberately future-dated
  `meta.timestamp` (`2099-01-01T00:00:00.000Z`) so the outputs shown in the user guides stay
  reproducible on a fresh clone — checkout-time source mtimes can never appear `newer` than it.
  To experiment with time-based staleness, run your own project's tests and point cov-loupe at
  the generated `coverage/coverage.json`.
- If you edit a fixture source file, update its entry in `coverage/coverage.json` as well: a
  line count that disagrees with the source is reported as a line-mismatch staleness.

Files include controllers, models, payments services, background jobs, and an API client. A few files are intentionally missing from the coverage file so the `--tracked-globs` examples surface gaps.

Related guides:
- [CLI Usage](../../user/CLI_USAGE.md)
- [Examples](../../user/EXAMPLES.md)
