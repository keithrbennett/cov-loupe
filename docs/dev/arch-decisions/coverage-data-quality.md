# Coverage Data Quality

[Back to main README](../../index.md)

This document describes how cov-loupe ensures the accuracy and reliability of coverage data through staleness detection.

## Coverage Staleness Detection

### Status

Accepted

### Context

Coverage data can become outdated when source files are modified after tests run. This creates misleading results:

- Coverage percentages appear lower/higher than reality
- Line numbers in coverage reports don't match the current source
- AI agents and users may make decisions based on stale data

We needed a staleness detection system that could:

1. Detect when source files have been modified since coverage was collected
2. Detect when source files have different line counts than coverage data
3. Handle edge cases (deleted files)
4. Support both file-level and project-level checks
5. Allow users to control whether staleness is reported or causes errors

#### Alternative Approaches Considered

1. **No staleness checking**: Simple, but leads to confusing/incorrect reports
2. **Single timestamp check**: Fast, but misses line count mismatches (files edited and reverted)
3. **Content hashing**: Accurate, but expensive for large projects
4. **Multi-type detection with modes**: More complex, but provides accurate detection with user control

### Decision

We implemented a **staleness detection system** with configurable error modes that can identify four distinct staleness conditions.

#### Four Staleness Types

The `StalenessChecker` class (defined in `lib/cov_loupe/staleness/staleness_checker.rb`) detects four distinct types of staleness:

1. **Type "error" (Error)**: The staleness check itself failed
   - Returned by `CoverageModel#staleness_for` when an exception is raised during staleness checking
   - Example: File permission errors, resolver failures, or other unexpected issues
   - The error is logged but execution continues with an "error" status instead of crashing

2. **Type "missing" (Missing)**: The source file exists in coverage but is now deleted/missing
   - Returned by `file_staleness_status` when `File.file?(file_abs)` returns false
   - Example: File was deleted after tests ran

3. **Type "newer" (Timestamp)**: The source file's mtime is newer than coverage timestamp
   - Detected by comparing `File.mtime(file_abs)` with coverage timestamp
   - Example: File was edited after tests ran

4. **Type "length_mismatch" (Length)**: The source file line count doesn't match the coverage lines array length
   - Detected by comparing `File.foreach(path).count` with `coverage_lines.length`
   - Example: Lines were added/removed without changing mtime (rare but possible with version control)

5. **Type "ok" (Not stale)**: The file is not stale
   - Returned when none of the above staleness conditions apply
   - Indicates the coverage data is current and accurate

#### Implementation Details

The core algorithm lives in `CovLoupe::StalenessChecker#compute_file_staleness_details`:

```ruby
def compute_file_staleness_details(file_abs, coverage_lines)
  coverage_ts = coverage_timestamp
  exists = File.file?(file_abs)
  file_mtime = exists ? File.mtime(file_abs) : nil

  cov_len = coverage_lines.respond_to?(:length) ? coverage_lines.length : 0
  src_len = exists ? safe_count_lines(file_abs) : 0

  # If coverage timestamp is 0 (missing/invalid), we cannot determine if file is newer
  newer = if coverage_ts.to_i > 0
            !!(file_mtime && file_mtime.to_i > coverage_ts.to_i)
          else
            false
          end

  len_mismatch = (cov_len.positive? && src_len != cov_len)
  newer &&= !len_mismatch  # Prioritize length mismatch over timestamp

  {
    exists: exists,
    file_mtime: file_mtime,
    coverage_timestamp: coverage_ts,
    cov_len: cov_len,
    src_len: src_len,
    newer: newer,
    len_mismatch: len_mismatch
  }
end
```

#### Staleness Modes

The checker supports two modes, configured when instantiating `StalenessChecker`:

- **`:off`** (default): Staleness is detected but only reported in responses, never raises errors
- **"error"**: Staleness raises `CoverageDataStaleError` or `CoverageDataProjectStaleError`

This allows:
- Interactive tools to show warnings without crashing
- CI systems to fail builds on stale coverage
- AI agents to decide how to handle staleness based on their goals

#### File-Level vs Project-Level Checks

**File-level** (`check_file!` and `file_staleness_status`):
- Checks a single file's staleness
- Returns one of the staleness status strings ("ok", "missing", "newer", "length_mismatch", "error")
- Used by single-file tools (summary, detailed, uncovered)

**Project-level** (`check_project!`):
- Checks all covered files plus optionally tracked files
- Detects:
    - Files newer than coverage timestamp
    - Files deleted since coverage was collected
    - Tracked files missing from coverage (newly added files)
- Raises `CoverageDataProjectStaleError` with lists of problematic files
- Used by `project_coverage`

**Totals behavior**:
- `project_totals` excludes any stale files ("missing", "newer", "length_mismatch", "error") from aggregate counts.
- Totals include explicit `with_coverage`/`without_coverage` breakdowns so callers can reconcile what was omitted.
- The `without_coverage` payload includes counts for three categories:
    - `missing_from_coverage`: Tracked files that have no coverage data in the resultset
    - `unreadable`: Files that exist but could not be read (e.g., due to permission errors, I/O issues, or staleness check failures)
    - `skipped`: Files that were skipped during list processing due to coverage data errors (e.g., malformed entries)
- The `unreadable` count is populated from `list_result['unreadable_files']`, which is collected during staleness checking when files exist but cannot be accessed or validated.

#### Tracked Globs Feature

The project-level check supports `tracked_globs` parameter to detect newly added files:

```ruby
# Detects if lib/**/*.rb files exist that have no coverage data
checker.check_project!(coverage_map)  # with tracked_globs: ['lib/**/*.rb']
```

This helps teams ensure new files are included in test runs.

#### Resultset Path Consistency (SimpleCov)

SimpleCov can emit mixed path forms for the same file when resultsets are merged across suites or
environments (for example, absolute vs relative paths, or different roots). This is a SimpleCov
data consistency risk, not a cov-loupe behavior. Downstream tools that normalize paths may treat
one entry as overriding another when multiple keys map to the same absolute path.

**Guidance:** Keep `SimpleCov.root` consistent across all suites and avoid manual path rewriting
before merging resultsets.

### Consequences

#### Positive

1. **Accurate detection**: Three types catch different staleness scenarios comprehensively
2. **User control**: Modes allow errors or warnings based on use case
3. **Detailed information**: Staleness errors include specific file lists and timestamps
4. **Project awareness**: Can detect newly added files that lack coverage
5. **Conservative totals**: Aggregate totals only include fresh coverage data

#### Negative

1. **Complexity**: Three staleness types are harder to understand than a single timestamp check
2. **Performance**: Line counting and mtime checks for every file add overhead
3. **Ambiguity**: When multiple staleness types apply, prioritization logic (length > timestamp) may surprise users

#### Trade-offs

- **Versus timestamp-only**: More accurate but slower and more complex
- **Versus content hashing**: Fast enough for most projects, but can't detect "edit then revert" scenarios
- **Versus no checking**: Essential for reliable coverage reporting, worth the complexity

#### Edge Cases Handled

1. **Deleted files**: Appear as "missing" type staleness
2. **Empty files**: `cov_len.positive?` guard prevents false positives
3. **No coverage timestamp**: Defaults to 0, effectively disabling timestamp checks

### References

- Implementation: `lib/cov_loupe/staleness/staleness_checker.rb` (`StalenessChecker` class)
- File-level checking: `StalenessChecker#check_file!` and `#file_staleness_status`
- Project-level checking: `StalenessChecker#check_project!`
- Staleness detail computation: `StalenessChecker#compute_file_staleness_details`
- Error types: `lib/cov_loupe/errors/errors.rb` (`CoverageDataStaleError`, `CoverageDataProjectStaleError`)
- Usage in tools: `lib/cov_loupe/tools/project_coverage_tool.rb`, `lib/cov_loupe/model/model.rb`
