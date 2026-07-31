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
  spec.add_dependency 'mcp', '>= 0.15', '< 2.0'
  spec.add_dependency 'simplecov', '>= 0.21', '< 2.0'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.post_install_message = <<~MESSAGE

    If you are upgrading across major versions, review the relevant guides at
    docs/user/migrations/README.md for breaking change information.

  MESSAGE
end
