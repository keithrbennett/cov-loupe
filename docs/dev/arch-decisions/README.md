# Architecture Decision Records

[Back to main README](../../index.md) | [Architecture Overview](../ARCHITECTURE.md)

## What is an ADR?

An Architecture Decision Record (ADR) captures a significant architectural decision made during the development of this project, along with its context and consequences.

## ADR Format

Each ADR follows this structure:

### Title
A short phrase describing the decision (e.g., "Dual-Mode Operation: CLI and MCP Server")

### Status
- **Accepted**: The decision has been made and is currently in effect
- **Proposed**: Under consideration
- **Deprecated**: No longer applicable
- **Superseded**: Replaced by a newer decision

### Context
The background, problem statement, and constraints that led to the decision.

### Decision
The architectural choice that was made.

### Consequences
The implications of this decision, both positive and negative. This includes:
- Benefits gained
- Trade-offs accepted
- Complexity introduced
- Future constraints

### References
Links to related code, issues, documentation, or other ADRs.

## Index of ADRs

ADRs are organized by topic area rather than chronologically:

- [Application Architecture](application-architecture.md) - Dual-mode operation (CLI/MCP) and context-aware error handling
- [Coverage Data Quality](coverage-data-quality.md) - Staleness detection system
- [Output Character Mode](output-character-mode.md) - Global ASCII vs Unicode output control
- [Path Resolution](path-resolution.md) - Path matching strategy and cross-OS coverage support
- [Policy Validation](policy-validation.md) - Validation predicates using Ruby `instance_eval`
- [SimpleCov Integration](simplecov-integration.md) - Dependency strategy and data loading (replaced)

## When to Create an ADR

Create an ADR when:
- Making a decision that affects the structure or behavior of the system
- Choosing between multiple viable approaches
- Accepting significant trade-offs
- Making decisions that future maintainers should understand

## Contributing

When adding a new ADR:
1. Add it to the appropriate topic-based file, or create a new file if it covers a new area
2. Follow the format outlined above
3. Update this README's index
4. Link to relevant code and documentation
