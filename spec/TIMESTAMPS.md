# Test Timestamp Documentation

This document explains the timestamp constants used throughout the test suite for consistent and documented test data.

## Constants (defined in `spec_helper.rb`)

### `FIXTURE_COVERAGE_TIMESTAMP = 1_720_000_000`
- **Human readable**: 2024-07-03 09:46:40 UTC (July 3rd, 2024)
- **Purpose**: The "generated" timestamp for the mocked `coverage.json` documents built by `CoverageFileMockHelpers`
- **Usage**: Used in tests that verify timestamp parsing and calculations with realistic coverage data

### `VERY_OLD_TIMESTAMP = 1`
- **Human readable**: 1970-01-01 00:00:01 UTC (Unix epoch + 1 second)
- **Purpose**: Simulates extremely stale coverage data (much older than any real file). It is 1, not 0, because 0 means a missing or invalid timestamp, which disables time-based staleness checks.
- **Usage**: Used in staleness tests to force stale coverage scenarios

### `TEST_FILE_TIMESTAMP = 1_000`
- **Human readable**: 1970-01-01 00:16:40 UTC (16 minutes and 40 seconds after epoch)
- **Purpose**: Used for stale error formatting tests to create predictable time deltas
- **Usage**: Creates a 999-second (16m 39s) difference from `VERY_OLD_TIMESTAMP` for delta calculations

## Conversion Reference

To convert timestamps for debugging:

```bash
# Unix timestamp to human readable
date -u -d @1720000000        # GNU date; on macOS: date -u -r 1720000000
# Wed Jul  3 09:46:40 UTC 2024

# Human readable to Unix timestamp  
date -d "2024-07-03 09:46:40 UTC" +%s   # GNU date; on macOS: date -j -u -f "%Y-%m-%d %H:%M:%S" "2024-07-03 09:46:40" +%s
# 1720000000
```

## Why These Values?

- **Realistic but static**: `FIXTURE_COVERAGE_TIMESTAMP` is a realistic recent date that won't change
- **Predictable deltas**: The differences between timestamps create predictable test scenarios
- **Clear intent**: Named constants make it obvious what each timestamp represents in tests

## Files Using These Constants

- `spec/support/coverage_file_mock_helpers.rb` - Writes `FIXTURE_COVERAGE_TIMESTAMP` into mocked coverage.json documents
- `spec/cov_loupe/repositories/coverage_repository_spec.rb` and `spec/cov_loupe/base_tool_spec.rb` - Use `FIXTURE_COVERAGE_TIMESTAMP`
- `spec/cov_loupe/staleness/model_staleness_spec.rb` - Tests staleness detection logic
- `spec/cov_loupe/model/model_error_handling_spec.rb` - Tests model errors for stale coverage
- `spec/cov_loupe/errors/errors_stale_spec.rb` - Tests stale error message formatting (also uses `TEST_FILE_TIMESTAMP`)
- `spec/cov_loupe/cli/cli_error_spec.rb` - Tests CLI error handling for stale coverage
