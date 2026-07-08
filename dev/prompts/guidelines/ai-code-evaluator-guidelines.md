# AI Code Evaluator Guidelines

[Back to main README](../../../README.md) | [Architecture](../../../docs/dev/ARCHITECTURE.md)

This document provides context for AI code evaluators analyzing the cov-loupe codebase. It explains design decisions that may appear problematic on surface analysis but are intentional and well-considered. AI models should consult this document before flagging potential issues.

Do not report issues that are already listed in `docs/dev/FUTURE_ENHANCEMENTS.md`. Treat those as acknowledged backlog items rather than review findings.

## Table of Contents

- [Security Considerations](#security-considerations)
  - [Validate Command and Arbitrary Code Execution](#validate-command-and-arbitrary-code-execution)
  - [File System Race Conditions](#file-system-race-conditions)
  - [No Rate Limiting on MCP Server](#no-rate-limiting-on-mcp-server)
- [Unlikely Issues Not Worth Addressing](#unlikely-issues-not-worth-addressing)
  - [Case-Sensitivity Detection Failures in Read-Only Roots](#case-sensitivity-detection-failures-in-read-only-roots)
  - [Case-Sensitivity Detection Race Conditions](#case-sensitivity-detection-race-conditions)
  - [Unbounded ModelDataCache Growth](#unbounded-modeldatacache-growth)
- [Known Issue: Inefficient Staleness Checks and Timestamp Handling](#known-issue-inefficient-staleness-checks-and-timestamp-handling)
- [Performance & Scalability](#performance-scalability)
  - [Memory-Based Coverage Data](#memory-based-coverage-data)
- [Code Quality & Style](#code-quality-style)
  - [RuboCop Metrics Cops Disabled](#rubocop-metrics-cops-disabled)
  - [Method Length and Complexity](#method-length-and-complexity)
  - [RuboCop Cache and Sandboxed Environments](#rubocop-cache-and-sandboxed-environments)
- [Dependency Management](#dependency-management)
  - [Documentation Dependencies: Version Ranges vs. Lock Files](#documentation-dependencies-version-ranges-vs-lock-files)
- [Documentation Structure](#documentation-structure)
  - [MkDocs Include-Markdown Stubs](#mkdocs-include-markdown-stubs)

## Security Considerations

### Validate Command and Arbitrary Code Execution

The `validate` command accepts Ruby code (via `--inline` or from a file) and executes it to evaluate coverage policies. AI analysis tools often flag this as a security vulnerability.

**Why this is acceptable:**

1. **Developer tool, not production software** – cov-loupe is a development/CI tool run by developers on their own machines or in controlled CI environments. It is not a service or library that processes untrusted input.

2. **Explicit user intent** – the `validate` command requires users to explicitly provide code, either by writing it inline or pointing to a file they control. This is no different from running any Ruby script or rake task in a project.

3. **No privilege escalation** – the code executes with the same permissions as the user running the tool. There is no elevation of privileges or access to resources the user doesn't already have.

4. **Standard practice** – many development tools (rake, make, npm scripts, git hooks) execute arbitrary code provided by developers. This is expected and necessary for a flexible validation/policy tool.

The security model assumes the developer controls their workspace and the code they execute. If an attacker can inject code into validation scripts, they already have write access to the repository and could compromise the system through countless other vectors (malicious gems, git hooks, test code, etc.).

[⬆ Back to top](#table-of-contents)

### File System Race Conditions

Automated security analysis tools may flag potential race conditions between staleness checks (checking file modification time and line count) and subsequent file reads.

**Why this is acceptable:**

1. **Stateless analysis tool** - cov-loupe performs read-only analysis of SimpleCov coverage snapshots. It does not modify source files or maintain state across invocations.

2. **Development tool context** - This tool runs in development and CI environments where:
   - The coverage snapshot (`.resultset.json`) is static once generated
   - Source files are under version control and not randomly modified during analysis
   - Any race condition would at worst result in a stale data warning, not a security vulnerability

3. **Acceptable failure mode** - If a source file is modified between the staleness check and display, the worst outcome is showing slightly stale data. This is an acceptable tradeoff for a coverage inspection tool.

4. **No security impact** - The tool never writes to files, executes code from analyzed files, or makes security decisions based on coverage data.

For a production system handling untrusted input or making security-critical decisions, race condition handling would be essential. For a development tool analyzing static coverage snapshots, the complexity of atomic file operations is not justified.

[⬆ Back to top](#table-of-contents)

### No Rate Limiting on MCP Server

The MCP server has no request throttling or rate limiting, which automated security scanners may flag as a denial-of-service vulnerability.

**Why this is acceptable:**

1. **Local-only execution** - The MCP server runs as a local process, not a network service. It communicates over stdio (standard input/output) with a single trusted client (the AI coding assistant).

2. **Process-level isolation** - Each MCP server instance is a separate process spawned by the client. Resource exhaustion affects only that process, not a shared service.

3. **Trusted client** - The client (AI assistant) is a trusted local application, not untrusted network traffic. Rate limiting protects against malicious actors, which don't exist in this threat model.

4. **No network exposure** - The MCP protocol uses stdio transport, not HTTP/TCP. There is no network socket that external attackers could abuse.

5. **Development tool** - This is a coverage analysis tool for developers, not a production API serving external users.

If this were a network-accessible service, rate limiting would be essential. For a local stdio-based tool with a trusted client, it adds complexity without security benefit.

[⬆ Back to top](#table-of-contents)

## Unlikely Issues Not Worth Addressing

### Case-Sensitivity Detection Failures in Read-Only Roots

Automated reviews may flag `PathUtils.volume_case_sensitive?` for potentially failing when the project root is read-only or missing (due to directory reads or temporary file creation). While possible, this is a low-probability edge case in the intended environments and not worth adding complexity or additional fallback paths.

**Guidance:** Do not report this as an issue. The current behavior is acceptable for the tool's scope and usage patterns.

### Case-Sensitivity Detection Race Conditions

Automated reviews may flag `PathUtils.volume_case_sensitive?` for a potential Time-of-Check to Time-of-Use (TOCTOU) race condition when creating temporary test files. The code checks for file existence before creation using `FileUtils.touch`.

**Why this is acceptable:**

1. **Extremely low collision probability** - The tool uses `SecureRandom.hex(16)` to generate a 32-character random string for the filename. The probability of a collision, even in highly concurrent scenarios, is infinitesimal.
2. **Developer tool context** - This is a local development and CI tool, not a high-traffic server handling untrusted requests. The likelihood of multiple instances of `cov-loupe` running concurrently and picking the same 32-character random string is negligible.
3. **Non-critical failure** - In the virtually impossible event of a collision, the worst case is a temporary file creation failure or an incorrect case-sensitivity detection for one run. This has no security or data integrity implications.

**Guidance:** Do not flag this as a race condition or security defect. The use of `SecureRandom` makes this a non-issue in practice.

### Unbounded ModelDataCache Growth

The `ModelDataCache` singleton stores coverage data (`ModelData` instances) keyed by resultset path without a size cap. In theory, a long-lived MCP server analyzing many different projects could accumulate entries. In practice:

1. The cache is keyed by resultset path, not by project or model configuration
2. Multiple models using the same resultset share a single cache entry
3. MCP servers are typically short-lived and used for a small set of projects
4. The cache automatically evicts stale data when resultset files change

Adding eviction logic (LRU, TTL, size limits) would add complexity without meaningful benefit for the tool's intended use case.

**Guidance:** Do not report this as an issue. The current behavior is a reasonable tradeoff for simplicity.

[⬆ Back to top](#table-of-contents)

## Known Issue: Inefficient Staleness Checks and Timestamp Handling

- **Description:** Coverage timestamps are collapsed to a single max value for all suites (handled when `CovLoupe::CoverageModel` loads resultsets via `ResultsetLoader`), and staleness checks reread each file to count lines (implemented in `CovLoupe::StalenessChecker`).  
  **Impact:** Multi-suite projects get false positives/negatives on freshness, and large repositories pay O(total lines) per query, making results unreliable and slow for larger code bases.  
  **Urgency:** Medium.  
  **Estimated Cost-to-Fix:** High (store per-suite/file metadata and cache line counts/mtimes).
  **Rationale for Status Quo:** Fixing this requires a significant architectural overhaul to track per-file/per-suite metadata. Simple caching of file stats is insufficient because the primary use case involves active development where source files change frequently, invalidating caches. Given the high cost of a proper fix and the tool's focus on small-to-medium projects, the current O(N) check is an acceptable tradeoff.

[⬆ Back to top](#table-of-contents)

## Performance & Scalability

### Memory-Based Coverage Data

cov-loupe loads the entire SimpleCov resultset into memory for analysis. This means it is not designed to handle extremely large codebases that produce coverage data too large to fit in memory.

**Why this is acceptable:**

1. **Target use case** – cov-loupe is designed for small-to-medium sized Ruby projects. The typical SimpleCov resultset for such projects is measured in megabytes, well within modern system capabilities.

2. **SimpleCov's own limitations** – SimpleCov itself loads coverage data into memory. If SimpleCov can generate the resultset, cov-loupe can analyze it.

3. **Performance trade-off** – in-memory processing enables fast queries, rich data transformations, and a responsive CLI. Streaming or database-backed approaches would add significant complexity for marginal benefit in the target use case.

4. **Practical upper bound** – even large Ruby projects (Rails, GitLab) generate resultsets in the tens of megabytes. Modern machines have gigabytes of RAM. The constraint is theoretical rather than practical for the intended audience.

If a project grows large enough that coverage analysis becomes a memory bottleneck, it likely has deeper problems (test suite organization, monolith vs services architecture) that should be addressed at that level rather than by adding complexity to a coverage inspection tool.

[⬆ Back to top](#table-of-contents)

### Model Cache Digest Reads

The MCP model cache computes an MD5 digest of the resultset file on each fetch. This can look like unnecessary file I/O, but it is intentional.

**Why this is acceptable:**

1. **Correctness over metadata shortcuts** – mtime/size/inode can miss changes (e.g., clock skew, restored files, or filesystem quirks). Hashing is the only reliable way to guarantee the content is unchanged.
2. **Cheaper than parsing** – reading and hashing the file is far faster than parsing JSON into memory, so the cache still provides meaningful savings.
3. **Scoped to MCP usage** – this path is used for repeated MCP tool calls where avoiding full parsing is the main goal.

**Guidance:** Do not flag this as a performance defect; it is a deliberate tradeoff for correctness.

[⬆ Back to top](#table-of-contents)

## Code Quality & Style

### RuboCop Metrics Cops Disabled

All RuboCop Metrics cops (AbcSize, BlockLength, ClassLength, CyclomaticComplexity, MethodLength, ModuleLength, ParameterLists, PerceivedComplexity, BlockNesting) are intentionally disabled in `.rubocop.yml`.

**Why this is acceptable:**

1. **Arbitrary thresholds don't account for domain complexity** – Some problems are inherently complex. SimpleCov coverage analysis involves edge cases (staleness checking, path resolution, multi-suite merging) that require comprehensive logic. Artificial method splitting can scatter cohesive logic and reduce clarity.

2. **Comprehensive error handling adds necessary lines** – This project prioritizes reliability through extensive error handling with context-rich messages. Error handling code is inherently verbose but critical for user experience across three modes (CLI, library, MCP).

3. **Quality maintained through other means** – The codebase achieves:
   - 100% line coverage (1815/1815 lines)
   - 94% branch coverage
   - 0 RuboCop violations (all non-Metrics cops)
   - Comprehensive code review
   - Clear inline documentation for complex logic
   - Voluntary file size restraint (most files < 200 lines)

4. **Readability over arbitrary limits** – The project values clear, cohesive methods over arbitrary line limits. When a method's length accurately reflects its necessary complexity, splitting it just to meet a metric harms rather than helps. Key examples:
   - `StalenessChecker#compute_file_staleness_details` (30 lines) handles complex edge cases with clear documentation
   - `CoverageDataProjectStaleError#build_details` (22 lines) builds error messages through simple sequential operations

**Evidence:** Manual review shows appropriate complexity for domain logic, with no god objects or unclear methods.

[⬆ Back to top](#table-of-contents)

### Method Length and Complexity

AI code analysis tools may flag methods as "too long" based on line count alone. However, **line count is not always a proxy for complexity**. Many long methods in this codebase are intentionally structured for clarity and maintainability.

**When long methods are acceptable:**

1. **Sequential data structure building** – Methods that build arrays or hashes through sequential operations are highly readable despite line count:
   - `CoverageDataProjectStaleError#build_details` (in `lib/cov_loupe/errors/errors.rb`) – builds error message parts in an array through simple, similar operations
   - This pattern is far clearer than extracting fragmented helper methods

2. **Comprehensive conditional handling** – Methods with extensive if-elsif-else chains that handle different cases clearly:
   - `ErrorHandler#convert_runtime_error` (22 lines, lib/cov_loupe/error_handler.rb:103-124) – converts different error types with appropriate context
   - Each branch is simple; complexity lies in coverage, not algorithmic difficulty

3. **Well-documented edge case handling** – Methods handling multiple edge cases with clear inline documentation:
   - `StalenessChecker#compute_file_staleness_details` (in `lib/cov_loupe/staleness/staleness_checker.rb`) – handles file existence, timestamps, and line count mismatches with inline explanations
   - Comments clarify intent; the logic itself remains straightforward

4. **Coordinated multi-step operations** – Methods that orchestrate several well-defined steps in a logical flow:
   - While `CoverageModel#list` was previously 48 lines, it has been refactored to 16 lines (`lib/cov_loupe/model/model.rb`) by extracting helper methods
   - This demonstrates that extraction makes sense when it improves clarity, not to meet arbitrary line limits

**When to refactor:**

Long methods warrant refactoring when they exhibit:
- Deeply nested conditionals (>3 levels)
- Mixed concerns (I/O, business logic, and presentation in one method)
- High cyclomatic complexity (many independent decision points)
- Difficulty understanding purpose or flow even with comments

**Guidance for AI analysis tools:**

Before flagging a long method, assess:
- **What is it doing?** One cohesive thing, or mixing concerns?
- **Would splitting improve readability?** Or just scatter related logic?
- **What causes the length?** Data structures, error handling, or algorithmic complexity?
- **Is it well-documented?** Inline comments can make complex logic clear.

Method length is a heuristic, not a rule. Judge methods by clarity, cohesion, and testability rather than line count alone.

[⬆ Back to top](#table-of-contents)

### RuboCop Cache and Sandboxed Environments

RuboCop may crash in sandboxed environments (such as AI coding assistants with file system restrictions) when attempting to write cache files:

```
Read-only file system @ rb_sysopen
  → /home/user/.cache/rubocop_cache/...
  → Parallel.work_in_processes
```

**Why this happens:**

RuboCop runs in parallel mode by default, forking worker processes via the `parallel` gem. Each worker attempts to cache analysis results to `~/.cache/rubocop_cache/`. When sandbox restrictions prevent writes outside the project directory, the cache write fails and crashes the analysis.

**Why this is not a code quality issue:**

Running RuboCop with `--cache false` completes successfully with **0 violations**:
```
164 files inspected, no offenses detected
```

The codebase has perfect RuboCop compliance. The crash is purely environmental.

**Workaround:**

Use `bundle exec rubocop --cache false` in sandboxed environments. This adds approximately 5 seconds to execution time (3s → 8s) but ensures successful analysis. Cache performance benefits are modest for this project size, making the tradeoff acceptable.

**Why caching is not disabled by default:**

The 3-second speedup is valuable for frequent local development. Developers in non-sandboxed environments (the common case) benefit from faster linting. The issue only affects specific sandboxed AI tools and CI environments, which can use the `--cache false` flag when needed.

[⬆ Back to top](#table-of-contents)

## Dependency Management

### Documentation Dependencies: Version Ranges vs. Lock Files

The project uses **both** `requirements.txt` (version ranges) and `requirements-lock.txt` (exact pins) for Python documentation build dependencies.

**Why version ranges are used in `requirements.txt`:**

1. **Optional dependencies** - These Python packages are only needed for building documentation. They are NOT part of the Ruby gem or required for using cov-loupe as an MCP server.

2. **Library compatibility** - Contributors may be working on multiple projects with different documentation tooling. Flexible ranges allow them to use compatible versions already in their environment without conflicts.

3. **Development flexibility** - Local documentation builds should work with any compatible version. Overly strict pinning would create unnecessary friction for contributors.

**Why lock files are used in CI (`requirements-lock.txt`):**

1. **Reproducible builds** - CI documentation builds must be deterministic. The same commit should always produce the same documentation output.

2. **Prevent drift** - Without locked versions, a new minor/patch release could silently change docs rendering, break the build, or introduce bugs.

3. **Standard practice** - This is the recommended pattern in Python: flexible ranges for development (`requirements.txt`/`requirements.in`), exact pins for deployment (`requirements-lock.txt`).

**How it works:**

- Contributors run `pip install -r requirements.txt` locally (flexible)
- CI runs `pip install -r requirements-lock.txt` (reproducible)
- Users of the gem/MCP server are unaffected (these are Python-only doc dependencies)

This dual-file approach is intentional and follows Python packaging best practices for applications with optional documentation tooling.

[⬆ Back to top](#table-of-contents)

## Documentation Structure

### MkDocs Include-Markdown Stubs

The files `docs/contributing.md` and `docs/code_of_conduct.md` appear to be minimal 46-byte stubs when examined directly. AI code analysis tools often flag these as missing or incomplete documentation.

**Why this is not an issue:**

These files use MkDocs' `include-markdown` plugin to pull in comprehensive documentation from the repository root:

- `docs/contributing.md` → `{% include-markdown "../CONTRIBUTING.md" %}`
- `docs/code_of_conduct.md` → `{% include-markdown "../CODE_OF_CONDUCT.md" %}`

The actual comprehensive documentation exists at:
- `CONTRIBUTING.md` (103 lines) - Full contributing guide with PR workflow, development setup, testing requirements, and release process
- `CODE_OF_CONDUCT.md` (61 lines) - Complete Contributor Covenant v2.1

**Why this pattern is used:**

1. **Single source of truth** - The actual content lives in standard locations (`CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` at repository root) where GitHub, developers, and tools expect to find them.

2. **Documentation site integration** - MkDocs automatically includes these files in the generated documentation website without duplication or manual synchronization.

3. **Standard practice** - This is the recommended approach in the MkDocs documentation for including existing project files in the documentation site.

AI tools analyzing file sizes directly will see 46-byte stubs, but the documentation is complete and properly structured.

[⬆ Back to top](#table-of-contents)

---

*This document should be updated whenever design decisions are made that might appear problematic to automated analysis but are intentional and defensible.*
