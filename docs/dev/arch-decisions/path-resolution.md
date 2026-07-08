# Path Resolution Strategy

[Back to ADR Index](README.md)

## Cross-OS Coverage Data Support

### Status
**Accepted** (2025-12-26)

### Context

SimpleCov's `.resultset.json` files contain file paths as keys in the coverage data hash. These paths are typically absolute paths from the machine where tests were run. Different operating systems use different path separators:
- Unix/Linux/macOS: `/`
- Windows: `\` (backslash)

Early versions of cov-loupe included path normalization logic that converted backslashes to forward slashes, enabling cross-platform path matching. This was motivated by a theoretical use case: analyzing a `.resultset.json` file generated on one OS (e.g., Windows) on a different OS (e.g., Linux/macOS).

Upon closer examination, this cross-OS scenario is unrealistic for several reasons:

1. **CI/CD workflows** – While coverage files might be generated in CI (often Linux), developers typically either:
   - Re-run tests locally to generate fresh coverage
   - View coverage reports rendered by SimpleCov's HTML formatter
   - Use hosted coverage services (Codecov, Coveralls)

2. **Docker development** – When tests run in containers, volume mounting ensures paths already match the host environment

3. **Path structure differences** – Cross-OS paths differ in more ways than just separators (drive letters, root paths, etc.), making simple separator normalization insufficient

4. **Same-machine path variations** – The legitimate use case is handling different working directories or relative vs absolute paths on the *same* machine, not across different OSes

### Decision

**Do not support analyzing `.resultset.json` files across different operating systems.**

Specifically:
- Normalize backslashes to forward slashes on Windows only
- Apply case-insensitive path matching on Windows (filesystem is case-insensitive)
- Apply case-sensitive path matching on Unix (filesystem is case-sensitive)
- Keep path resolution focused on same-OS scenarios:
    - Exact absolute path matching
    - Relative path matching (stripping project root)
- Trust that paths in coverage data use the native separator for the OS where cov-loupe runs

### Consequences

**Benefits:**
- **Simpler code** – No need for path separator normalization logic
- **Clearer semantics** – Path matching behavior is more predictable
- **Fewer edge cases** – No ambiguity around mixed separator styles
- **Honest API** – We don't promise cross-OS compatibility we can't fully deliver

**Trade-offs:**
- Users cannot analyze Windows `.resultset.json` files on Linux/macOS or vice versa
    - This is acceptable because this scenario is impractical anyway
    - Users who encounter this should re-run tests in their current environment

**No impact on:**
- Same-OS path resolution (absolute, relative)
- Normal development workflows
- CI/CD integration
- Docker/container-based development

### Implementation

Path normalization is centralized in the `PathUtils` module (`lib/cov_loupe/paths/path_utils.rb`). It handles:
- Normalizing path separators (backslashes to forward slashes on Windows)
- Case normalization for case-insensitive volumes (autodetected or explicit)
- Path cleaning

`CoverageLineResolver` delegates all path normalization to `PathUtils.normalize`, avoiding scattered platform checks and keeping the resolver logic focused on lookup strategies.

#### Path Comparison Strategy

Path comparison uses a **normalize-for-comparison-only** approach rather than normalize-and-store:

- **Original paths are preserved** - `PathUtils.expand` preserves the original case to avoid corrupting displayed file paths
- **Normalization happens at comparison time** - The `normalized_start_with?` helper method normalizes both paths internally for comparison but doesn't modify the originals
- **Boundary checking** - Prevents false matches where a path starts with a prefix string but isn't actually within that directory (e.g., `/home/user/project` should not match `/home/user/project-backup/file.rb`)

This approach ensures:
1. User-visible paths maintain original casing for better UX
2. Path matching works correctly on case-insensitive volumes (Windows, most macOS)
3. Mixed path separators (forward slash vs backslash) are handled transparently
4. Directory boundary checking prevents incorrect prefix matches

### References

- Implementation: `lib/cov_loupe/resolvers/coverage_line_resolver.rb` (delegates to `PathUtils`)
- Central Logic: `lib/cov_loupe/paths/path_utils.rb`
- Related tests removed: `spec/cov_loupe/resolvers/coverage_line_resolver_spec.rb` (cross-OS separator normalization context)
