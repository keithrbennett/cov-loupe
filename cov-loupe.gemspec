# frozen_string_literal: true

require_relative 'lib/cov_loupe/version'

Gem::Specification.new do |spec|
  spec.name          = 'cov-loupe'
  spec.version       = CovLoupe::VERSION
  spec.authors       = ['Keith R. Bennett']
  spec.email         = ['keithrbennett@gmail.com']

  spec.summary       = 'MCP server + CLI for SimpleCov coverage data'
  spec.description   = 'Provides an MCP (Model Context Protocol) server and a CLI to inspect ' \
                       'SimpleCov coverage, including per-file summaries and uncovered lines.'
  spec.license       = 'MIT'

  spec.homepage      = 'https://github.com/keithrbennett/cov-loupe'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.start_with?('spec/', 'test/')
    end.select do |f|
      f.start_with?('lib/', 'exe/', 'docs/', 'dev/', 'examples/') ||
        f.end_with?('.md') ||
        f.start_with?('LICENSE')
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = ['cov-loupe']
  spec.require_paths = ['lib']

  # Runtime deps (stdlib: json, time, pathname, yaml)
  spec.add_dependency 'amazing_print', '~> 2.0'
  spec.add_dependency 'logger'
  # MCP 0.15 is the minimum supported version because earlier releases reported tool
  # argument-validation failures as top-level JSON-RPC errors. Since 0.15, those failures are
  # tools/call results with isError: true, which is cov-loupe's documented response contract.
  spec.add_dependency 'mcp', '>= 0.15', '< 1.0'
  spec.add_dependency 'simplecov', '>= 0.21', '< 1.0'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.post_install_message = <<~MESSAGE
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃ V2.0.0 BREAKING CHANGES (if upgrading from v1.x)                          ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                           ┃
    ┃  • Options must now come BEFORE subcommands                               ┃
    ┃  • --stale renamed to --staleness (-S still works)                        ┃
    ┃  • --json replaced with --format json                                     ┃
    ┃  • Error modes renamed: 'on' → 'log', 'trace' → 'debug'                   ┃
    ┃  • --success-predicate moved to 'validate' subcommand                     ┃
    ┃  • Default sort order changed from ascending to descending                ┃
    ┃                                                                           ┃
    ┃ See docs/user/migrations/MIGRATING_TO_V2.md for complete migration guide. ┃
    ┃                                                                           ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃ V3.0.0 - GEM RENAMED: simplecov-mcp → cov-loupe                           ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                           ┃
    ┃ This gem has been renamed! If upgrading from simplecov-mcp:               ┃
    ┃                                                                           ┃
    ┃  • Executable: simplecov-mcp → cov-loupe                                  ┃
    ┃  • Environment: SIMPLECOV_MCP_OPTS → COV_LOUPE_OPTS                       ┃
    ┃  • Log file: simplecov_mcp.log → cov_loupe.log                            ┃
    ┃  • Alias: smcp → clp (in documentation)                                   ┃
    ┃                                                                           ┃
    ┃ Module name (CovLoupe) and require path (cov_loupe) unchanged.            ┃
    ┃                                                                           ┃
    ┃ Uninstall old gem: gem uninstall simplecov-mcp                            ┃
    ┃                                                                           ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃ V4.0.0 BREAKING CHANGES                                                   ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                           ┃
    ┃  ⚠️  MCP MODE NOW REQUIRES -m/--mode mcp FLAG (AUTO-DETECTION REMOVED)    ┃
    ┃                                                                           ┃
    ┃  If you use cov-loupe as an MCP server, you MUST update your config.      ┃
    ┃  Without -m mcp, the server will run in CLI mode and hang.                ┃
    ┃                                                                           ┃
    ┃  📖 Migration instructions: docs/user/migrations/MIGRATING_TO_V4.md       ┃
    ┃                                                                           ┃
    ┃ Other breaking changes:                                                   ┃
    ┃  • --force-mode removed → use -m/--mode cli|mcp instead                   ┃
    ┃  • --staleness removed → use --raise-on-stale (boolean) instead           ┃
    ┃  • Ruby API: check_stale removed → use raise_on_stale (boolean) instead   ┃
    ┃  • Model #all_files_coverage method renamed to #list                      ┃
    ┃                                                                           ┃
    ┃ See RELEASE_NOTES.md for full migration details.                          ┃
    ┃                                                                           ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃ V5.0.0 BREAKING CHANGES                                                   ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                           ┃
    ┃  • `cov-loupe version` subcommand removed                                 ┃
    ┃    Use -v / --version instead (prints bare version string and exits)      ┃
    ┃                                                                           ┃
    ┃  📖 Migration instructions: docs/user/migrations/MIGRATING_TO_V5.md       ┃
    ┃                                                                           ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃ V6.0.0 BREAKING CHANGES                                                   ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                           ┃
    ┃  • `--log-file stdout` / `-l stdout` is no longer permitted in any mode   ┃
    ┃    Logs are diagnostics and must not corrupt command output on stdout.    ┃
    ┃    Use `-l stderr`, a file path, or `-l :off` instead.                    ┃
    ┃                                                                           ┃
    ┃  • --format short codes/long names normalized (see below)                 ┃
    ┃    'p' now means puts (was pretty_json); 'J' now means pretty_json.       ┃
    ┃    'ap'/awesome_print no longer accepted; use 'a'/amazing_print.          ┃
    ┃    New formats added: inspect (i), puts (p), pretty_print (P).            ┃
    ┃                                                                           ┃
    ┃  • MCP tool-call failures now return results with isError: true.          ┃
    ┃    Requires mcp >= 0.15; upgrade applications pinned to older versions.   ┃
    ┃                                                                           ┃
    ┃  📖 Migration instructions: docs/user/migrations/MIGRATING_TO_V6.md       ┃
    ┃                                                                           ┃
    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
  MESSAGE
end
