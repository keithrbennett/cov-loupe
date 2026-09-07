# Test Timestamp Documentation

This document explains the timestamp constants used throughout the test suite for consistent and documented test data.

## Constants (defined in `spec_helper.rb`)

### `FIXTURE_COVERAGE_TIMESTAMP = 1_720_000_000`
- **Human readable**: 2024-07-03 16:26:40 UTC (July 3rd, 2024)
- **Purpose**: The "generated" timestamp for the mocked `coverage.json` documents built by `CoverageFileMockHelpers`
- **Usage**: Used in tests that verify timestamp parsing and calculations with realistic coverage data

### `VERY_OLD_TIMESTAMP = 0`
- **Human readable**: 1970-01-01 00:00:00 UTC (Unix epoch)
- **Purpose**: Simulates extremely stale coverage data (much older than any real file)
- **Usage**: Used in staleness tests to force stale coverage scenarios

### `TEST_FILE_TIMESTAMP = 1_000`
- **Human readable**: 1970-01-01 00:16:40 UTC (16 minutes and 40 seconds after epoch)
- **Purpose**: Used for stale error formatting tests to create predictable time deltas
- **Usage**: Creates a 1000-second (16m 40s) difference from `VERY_OLD_TIMESTAMP` for delta calculations

## Conversion Reference

To convert timestamps for debugging:

```bash
# Unix timestamp to human readable
date -d @1720000000
# Wed Jul  3 16:26:40 UTC 2024

# Human readable to Unix timestamp  
date -d "2024-07-03 16:26:40 UTC" +%s
# 1720000000
```

## Why These Values?

- **Realistic but static**: `FIXTURE_COVERAGE_TIMESTAMP` is a realistic recent date that won't change
- **Predictable deltas**: The differences between timestamps create predictable test scenarios
- **Clear intent**: Named constants make it obvious what each timestamp represents in tests

## Files Using These Constants

- `spec/util_spec.rb` - Tests timestamp parsing from fixture
- `spec/model_staleness_spec.rb` - Tests staleness detection logic
- `spec/errors_stale_spec.rb` - Tests stale error message formatting
- `spec/cli_error_spec.rb` - Tests CLI error handling for stale coverage
- `spec/support/coverage_file_mock_helpers.rb` - Writes the timestamp into mocked coverage.json documents