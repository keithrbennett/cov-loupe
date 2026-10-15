# frozen_string_literal: true

module CovLoupe
  # @api private
  module Resources
    REPOSITORY_URL = 'https://github.com/keithrbennett/cov-loupe'
    DOCUMENTATION_WEB_URL = 'https://keithrbennett.github.io/cov-loupe/'
    SCREENCAST_URL = 'https://www.bbs-software.com/screencasts/cov-loupe'
    LOCAL_README_PATH = File.expand_path('../../README.md', __dir__).freeze

    # Canonical resource map – single source of truth for both CLI and MCP.
    RESOURCE_MAP = {
      'repo'       => REPOSITORY_URL,
      'docs'       => DOCUMENTATION_WEB_URL,
      'docs-local' => LOCAL_README_PATH,
    }.freeze

    def self.cli_url_for(name)
      RESOURCE_MAP[name] || (raise UsageError,
        "Unknown resource: '#{name}'. Valid resources: #{RESOURCE_MAP.keys.sort.join(', ')}")
    end
  end
end
