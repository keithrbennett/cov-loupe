# Policy Validation

[Back to main README](../../index.md)

This document describes how cov-loupe allows users to define and enforce custom coverage policies through success predicates.

## Ruby `instance_eval` for Success Predicates

### Status

Accepted

### Context

cov-loupe needed a mechanism for users to define custom coverage policies beyond simple percentage thresholds. Different projects have different requirements:

- Some want all files above 80%, others allow a few files below threshold
- Some need different thresholds for different directories (e.g., 90% for API code, 60% for legacy)
- Some want total project coverage minimums
- CI/CD pipelines need exit codes based on policy compliance

We considered several approaches:

1. **Built-in policy DSL**: Define a limited language for expressing policies (e.g., YAML/JSON config)
2. **Plugin architecture**: Define a protocol/interface, require users to create Ruby classes implementing it
3. **Ruby file evaluation**: Load and execute arbitrary Ruby code that returns a callable predicate
4. **Sandboxed DSL**: Use a restricted Ruby environment (e.g., `$SAFE` levels, isolated VMs)

#### Key Requirements

- Flexibility: Support arbitrarily complex coverage policies
- Simplicity: Easy for users to write and understand
- Debuggability: Users can use standard Ruby debugging tools
- CI/CD integration: Clear exit codes (0 = pass, 1 = fail, 2 = error)
- Access to coverage data: Predicates need access to the full `CoverageModel` API

#### Why Not a Custom DSL?

A custom DSL would be:
- Limited in expressiveness (hard to predict all future use cases)
- Harder to debug (users can't use standard Ruby tools)
- More maintenance burden (parsing, validation, documentation)
- Still vulnerable to injection if it allowed any dynamic computation

#### Why Not Sandboxing?

Ruby's sandboxing options are limited:
- `$SAFE` levels were deprecated and removed in Ruby 2.7+
- Full VM isolation (Docker, etc.) is too heavy for a CLI tool
- Any Turing-complete sandbox can be escaped given enough effort
- True security requires not executing untrusted code at all

### Decision

We chose to **evaluate Ruby files using `instance_eval`** with prominent security warnings rather than attempting to create a false sense of security through incomplete sandboxing.

#### Implementation

The implementation is in `lib/cov_loupe/cli.rb` (`CoverageCLI#load_success_predicate`):

```ruby
def load_success_predicate(path)
  unless File.exist?(path)
    raise "Success predicate file not found: #{path}"
  end

  content = File.read(path)

  # WARNING: The predicate code executes with full Ruby privileges.
  # It has unrestricted access to the file system, network, and system commands.
  # Only use predicate files from trusted sources.
  #
  # We evaluate in a fresh Object context to prevent accidental access to
  # CLI internals, but this provides NO security isolation.
  evaluation_context = Object.new
  predicate = evaluation_context.instance_eval(content, path, 1)

  unless predicate.respond_to?(:call)
    raise "Success predicate must be callable (lambda, proc, or object with #call method)"
  end

  predicate
rescue SyntaxError => e
  raise "Syntax error in success predicate file: #{e.message}"
end
```

The predicate is then called with a `CoverageModel` instance:

```ruby
def run_success_predicate
  predicate = load_success_predicate(config.success_predicate)
  model = CoverageModel.new(**config.model_options)

  result = predicate.call(model)
  exit(result ? 0 : 1)  # 0 = success, 1 = failure
rescue => e
  warn "Success predicate error: #{e.message}"
  warn e.backtrace.first(5).join("\n") if config.error_mode == :debug
  exit 2  # Exit code 2 for predicate errors
end
```

#### Security Model: Treat as Executable Code

Rather than pretending to sandbox untrusted code, we treat success predicates **exactly like any other Ruby code in the project**:

1. **Prominent warnings** in documentation (highlighted near the top of `examples/success_predicates/README.md`):
   ```
   ⚠️ SECURITY WARNING

   Success predicates execute as arbitrary Ruby code with full system privileges.
   Only use predicate files from trusted sources.
   - Never use predicates from untrusted or unknown sources
   - Review predicates before use, especially in CI/CD environments
   - Store predicates in version control with code review
   ```

2. **Code review workflow**: Predicates live in version control alongside tests
3. **CI/CD best practices**: Same permissions model as running tests themselves
4. **Example predicates**: Well-documented examples showing safe patterns

#### Predicate API

Success predicates must be callable (lambda, proc, or object with `#call` method):

**Lambda example:**
```ruby
->(model) do
  model.list.all? { |f| f['percent_covered'] >= 80 }
end
```

**Class example:**

```ruby

class CoveragePolicy
  def call(model)
    api_files = model.list['files'].select { |f| f['file'].start_with?('lib/api/') }
    api_files.all? { |f| f['percent_covered'] >= 90 }
  end
end

AllFilesAboveThreshold.new
```

The predicate receives a full `CoverageModel` instance with access to:
- `list(tracked_globs:, sort_order:)` - All file coverage data
- `summary_for(path)` - Coverage summary for a specific file
- `uncovered_for(path)` - Uncovered lines for a specific file
- `detailed_for(path)` - Per-line coverage data

### Consequences

#### Positive

1. **Maximum flexibility**: Users can express arbitrarily complex coverage policies using full Ruby
2. **Familiar tooling**: Users can debug predicates with standard Ruby tools (pry, byebug, etc.)
3. **Simplicity**: No custom DSL to learn, document, or maintain
4. **Honesty**: Security model is clear and doesn't provide false confidence
5. **Composability**: Users can require other libraries, define helper methods, etc.
6. **Excellent examples**: We provide 5+ well-documented example predicates

#### Negative

1. **Security responsibility**: Users must understand the security implications
2. **Potential misuse**: Users might mistakenly trust untrusted predicate files
3. **No isolation**: Buggy predicates can access/modify anything in the system
4. **Documentation burden**: Must clearly communicate security model

#### Trade-offs

- **Versus custom DSL**: More powerful and debuggable, but requires user awareness of security
- **Versus plugin architecture**: Simpler (no gem dependencies, no protocol to learn), but same security profile
- **Versus incomplete sandboxing**: Honest about capabilities rather than security theater

#### Threat Model

This approach is **appropriate** when:
- Predicate files are stored in version control with code review
- Users treat predicates like any other code in their project (tests, Rakefile, etc.)
- CI/CD environments already execute arbitrary code (tests, build scripts)

This approach is **inappropriate** when:
- Processing untrusted predicate files from unknown sources
- Allowing users to upload predicates via web interface
- Running in a multi-tenant environment without isolation

#### Future Considerations

If demand arises for truly untrusted predicate execution, alternatives include:

1. **JSON-based policy format**: Limited expressiveness but safe
2. **WebAssembly sandbox**: Execute policies in an isolated WASM runtime
3. **External process**: Run predicates in separate process with restricted permissions

However, for the primary use case (CI/CD policy enforcement), the current approach is simpler and more flexible than these alternatives.

### References

- Implementation: `lib/cov_loupe/cli.rb` (`CoverageCLI#load_success_predicate` and `#run_success_predicate`)
- Security warnings: `examples/success_predicates/README.md`
- Example predicates: `examples/success_predicates/*.rb`
- CoverageModel API: `lib/cov_loupe/model.rb`
- CLI config: `lib/cov_loupe/cli_config.rb` (`success_predicate` field)
- Option parsing: `lib/cov_loupe/option_parser_builder.rb` (`--success-predicate` flag)
