# Future Enhancements

[Back to main README](../index.md)

## Coverage path lookup indexing

### Problem
Single-file tools (`summary`, `raw`, `detailed`, `uncovered`) call `CoverageLineResolver#resolve_key`, which normalizes every key in the coverage map on each lookup. That makes per-file queries O(n) in the number of files and can become O(n^2) across repeated MCP/CLI requests.

### Proposed approach
Precompute a normalized-key index once per resolver (or per cached model data). Use that index for O(1) lookups while preserving ambiguity detection when multiple original keys normalize to the same value.

### Why this matters
Large coverage files or frequent interactive queries can feel sluggish due to repeated normalization and full-map scans. Indexing would improve responsiveness without changing output semantics.
