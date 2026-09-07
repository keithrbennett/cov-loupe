# Test Documentation Examples

**Purpose:** Verify that all command examples in documentation work correctly and produce expected outputs.

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding so they can
   choose to start a new session in the project root.

---

## When to Use This

- After making documentation changes
- Before releases
- After CLI or API changes that might affect examples
- When suspecting docs are out of sync with code

## Scope

### Files to Test

Run all command examples found in:
- `README.md`
- `docs/user/**/*.md`
- `docs/dev/**/*.md`

### Files to Exclude

Do NOT test examples in:
- `docs/dev/arch-decisions/**/*.md`
- `docs/dev/presentations/**/*.md`

## Process

### 1. Extract Command Examples

Identify all code blocks that contain executable commands:
- Bash/shell commands
- CLI invocations
- Code that should produce specific output

Look for:
- Code blocks marked with `bash`, `sh`, `shell`, or `console`
- Inline code that appears to be runnable commands
- Example command outputs

### 2. Test Each Command

For each command found:

1. **Set up environment** (if needed):
   - Install dependencies
   - Create test files/fixtures
   - Set environment variables

2. **Execute the command** in an appropriate context:
   - Use the correct working directory
   - Ensure required files exist
   - Handle commands that require specific prerequisites

3. **Verify output**:
   - Check exit code (0 for success unless failure is expected)
   - Compare actual output with documented output
   - Verify expected files are created
   - Check for error messages if shown in docs

4. **Clean up** (if needed):
   - Remove temporary files
   - Reset environment

### 3. Document Failures

For each failing example, record:

- **File:** Which documentation file contains the failing example
- **Line/Section:** Where in the file (approximate line or section heading)
- **Command:** The exact command that failed
- **Expected:** What the documentation shows should happen
- **Actual:** What actually happened
- **Error:** Any error messages
- **Suggested Fix:** How to correct the documentation or code

## Common Issues to Check

### Syntax Changes
- Command options that have changed (`--old-flag` → `--new-flag`)
- Subcommands that have been renamed or removed
- New required parameters

### Path Assumptions
- Commands that assume specific working directories
- Relative vs absolute paths
- File paths that may not exist in all environments

### Output Format Changes
- JSON structure changes
- Table column changes
- Different error message text

### Prerequisites
- Missing setup steps (e.g., "First run X before running Y")
- Undocumented dependencies
- Configuration that must be set

### Version-Specific Examples
- Examples that only work with specific versions
- Deprecated features still documented

## Output Format

### If All Examples Pass

Briefly report success:
```
Tested X command examples across Y documentation files.
All examples executed successfully.
```

### If Examples Fail

Create a detailed report with:

```markdown
# Documentation Example Test Results

**Date:** YYYY-MM-DD
**Tested Files:** X
**Total Examples:** Y
**Failed:** Z

## Failures

### README.md

#### Line 42: cov-loupe list command
**Command:**
\`\`\`bash
cov-loupe list --format json
\`\`\`

**Expected:**
JSON output with coverage data

**Actual:**
```
Error: unknown option '--format'
```

**Issue:**
The `--format` flag has been replaced with `-f` or `--output-format`

**Suggested Fix:**
Update documentation to use:
\`\`\`bash
cov-loupe list --output-format json
\`\`\`

---

### docs/user/getting-started.md

#### Line 78: Running with custom coverage file

... (continue for each failure)

## Summary

- Update format flag in README.md line 42
- Add missing setup step in getting-started.md before line 78
- Fix output example in advanced-usage.md line 156 (JSON structure changed)
```

## Notes

- **Don't modify code:** This is a validation task, not a fix task. Document what needs changing.
- **Test in clean environment:** If possible, test in a fresh environment to catch missing setup steps.
- **Check both success and failure examples:** If documentation shows an error
  example, verify it produces that error.
- **Version compatibility:** Note if examples only work with specific versions.

## Follow-Up Actions

After identifying failures:
1. Create issues for documentation fixes
2. Update documentation files
3. Consider adding automated tests for critical examples
4. Re-run this validation after fixes
