# frozen_string_literal: true

require 'json'

require_relative '../errors/errors'
require_relative 'coverage_json_loader'
require_relative 'resultset_loader'

module CovLoupe
  # Front door for loading SimpleCov coverage data from disk. Reads the
  # file once, detects its format from the parsed structure, and routes to
  # the matching loader:
  #
  # - coverage.json (the documented JSON formatter output) is handled by
  #   CoverageJsonLoader
  # - .resultset.json (SimpleCov's internal merge cache) is handled by
  #   ResultsetLoader
  #
  # Detection is structural rather than filename-based, so an explicitly
  # provided path of either format loads correctly regardless of its name.
  class CoverageFileLoader
    def self.load(path:, logger: nil)
      logger ||= CovLoupe.logger
      raw = JSON.parse(File.read(path))

      if CoverageJsonLoader.coverage_json?(raw)
        CoverageJsonLoader.load_parsed(raw, path: path, logger: logger)
      else
        ResultsetLoader.load_parsed(raw, resultset_path: path, logger: logger)
      end
    end
  end
end
