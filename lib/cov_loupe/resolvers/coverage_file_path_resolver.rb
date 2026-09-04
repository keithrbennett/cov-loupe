# frozen_string_literal: true

require 'pathname'

require_relative '../deprecation'
require_relative '../errors/errors'
require_relative '../paths/path_utils'

module CovLoupe
  module Resolvers
    # Locates the coverage data file for a project: coverage.json (the
    # documented SimpleCov JSON formatter output) or .resultset.json
    # (SimpleCov's internal merge cache). coverage.json is preferred when
    # both exist.
    #
    # Resolution order:
    # 1. If the user provides an explicit path, resolve it (supports files and directories).
    #    A directory is searched in COVERAGE_FILE_NAMES order, so coverage.json inside it
    #    wins over .resultset.json.
    # 2. Otherwise, search DEFAULT_CANDIDATES relative to the project root and take the
    #    first file that exists. That list is ordered format-first, not location-first:
    #    every coverage.json location is tried before any .resultset.json location, so
    #    e.g. tmp/coverage.json is chosen over coverage/.resultset.json. Recency is never
    #    consulted; an explicit path is the way to pin a specific file.
    #
    # When a relative path is given, it is expanded against both the current working directory
    # and the project root. If both expansions point to valid locations, an ambiguity error
    # is raised to prevent silently using the wrong file.
    class CoverageFilePathResolver
      COVERAGE_FILE_NAMES = ['coverage.json', '.resultset.json'].freeze

      DEFAULT_CANDIDATES = [
        'coverage.json',
        'coverage/coverage.json',
        'tmp/coverage.json',
        '.resultset.json',
        'coverage/.resultset.json',
        'tmp/.resultset.json',
      ].freeze

      def initialize(root: Dir.pwd, candidates: DEFAULT_CANDIDATES)
        @root = root
        @candidates = candidates
      end

      def find_coverage_file(coverage_file: nil)
        if coverage_file && !coverage_file.empty?
          path = normalize_coverage_file_path(coverage_file)
          if (resolved = resolve_candidate(path, strict: true))
            return resolved
          end
        end

        resolve_fallback or raise_not_found_error
      end

      # Deprecated name for find_coverage_file. Removed in v7.0.0.
      def find_resultset(resultset: nil)
        Deprecation.warn('CoverageFilePathResolver#find_resultset', '#find_coverage_file')
        find_coverage_file(coverage_file: resultset)
      end

      private def resolve_candidate(path, strict:)
        return path if File.file?(path)
        return resolve_directory(path) if File.directory?(path)

        raise_not_found_error_for_file(path) if strict
        nil
      end

      private def resolve_directory(path)
        COVERAGE_FILE_NAMES.each do |name|
          candidate = File.join(path, name)
          return candidate if File.file?(candidate)
        end

        raise CoverageFileNotFoundError, "No coverage.json or .resultset.json found in directory: #{path}"
      end

      private def raise_not_found_error_for_file(path)
        raise CoverageFileNotFoundError, "Specified coverage file not found: #{path}"
      end

      private def resolve_fallback
        @candidates
          .map { |p| PathUtils.expand(p, @root) }
          .find { |p| File.file?(p) }
      end

      # Resolves a user-supplied coverage file argument to an absolute path.
      #
      # A relative argument is ambiguous: it could be relative to the working directory
      # or to the project root. The method expands against both and applies these rules:
      #   1. If both expansions point to valid locations, raise an ambiguity error.
      #   2. Return whichever single valid location exists (preferring pwd-expanded).
      #   3. If neither exists, prefer the pwd-expanded path when it falls inside the root,
      #      otherwise return the root-expanded path as the canonical form.
      private def normalize_coverage_file_path(coverage_file)
        expanded_coverage_file = PathUtils.expand(coverage_file, Dir.pwd)
        expanded_root = PathUtils.expand(coverage_file, @root)

        if ambiguous_coverage_file_path?(expanded_coverage_file, expanded_root)
          raise_ambiguous_coverage_file_error(expanded_coverage_file, expanded_root)
        end

        return expanded_coverage_file if valid_coverage_file_location?(expanded_coverage_file)
        return expanded_root if valid_coverage_file_location?(expanded_root)

        return expanded_coverage_file if within_root?(expanded_coverage_file)

        expanded_root
      end

      private def within_root?(path)
        PathUtils.within_root?(path, @root)
      end

      private def ambiguous_coverage_file_path?(expanded_pwd, expanded_root)
        return false if expanded_pwd == expanded_root

        valid_coverage_file_location?(expanded_pwd) && valid_coverage_file_location?(expanded_root)
      end

      private def valid_coverage_file_location?(path)
        return true if File.file?(path)
        return false unless File.directory?(path)

        COVERAGE_FILE_NAMES.any? { |name| File.file?(File.join(path, name)) }
      end

      private def raise_ambiguous_coverage_file_error(expanded_pwd, expanded_root)
        raise ConfigurationError,
          "Ambiguous coverage file location specified. Both #{expanded_pwd} and #{expanded_root} exist. " \
          'Use `./` or an absolute filespec to disambiguate.'
      end

      private def raise_not_found_error
        message = "Could not find coverage.json or .resultset.json under #{@root.inspect}; " \
                  'run tests or set --coverage-file option'
        CovLoupe.logger.error(message) if CovLoupe.logger
        raise CoverageFileNotFoundError, message
      end
    end

    # Deprecated name for CoverageFilePathResolver. Removed in v7.0.0.
    ResultsetPathResolver = CoverageFilePathResolver
  end
end
