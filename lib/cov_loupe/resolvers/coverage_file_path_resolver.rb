# frozen_string_literal: true

require_relative '../errors/errors'
require_relative '../paths/path_utils'

module CovLoupe
  module Resolvers
    # Locates a project's coverage.json, the SimpleCov JSON formatter output.
    #
    # Resolution order:
    # 1. If the user provides an explicit path, resolve it (supports files and directories).
    #    A directory must contain coverage.json.
    # 2. Otherwise, use DEFAULT_COVERAGE_FILE relative to the project root, which is where
    #    SimpleCov writes it by default.
    #
    # When a relative path is given, it is expanded against both the current working directory
    # and the project root. If both expansions point to valid locations, an ambiguity error
    # is raised to prevent silently using the wrong file.
    class CoverageFilePathResolver
      COVERAGE_FILE_NAME = 'coverage.json'

      DEFAULT_COVERAGE_FILE = 'coverage/coverage.json'

      def initialize(root: Dir.pwd)
        @root = root
      end

      def find_coverage_file(coverage_file: nil)
        if coverage_file && !coverage_file.empty?
          resolve_explicit_path(normalize_coverage_file_path(coverage_file))
        else
          resolve_default_path
        end
      end

      private def resolve_explicit_path(path)
        return path if File.file?(path)
        return resolve_directory(path) if File.directory?(path)

        raise CoverageFileNotFoundError, "Specified coverage file not found: #{path}"
      end

      private def resolve_directory(path)
        candidate = File.join(path, COVERAGE_FILE_NAME)
        return candidate if File.file?(candidate)

        raise CoverageFileNotFoundError, "No #{COVERAGE_FILE_NAME} found in directory: #{path}"
      end

      private def resolve_default_path
        path = PathUtils.expand(DEFAULT_COVERAGE_FILE, @root)
        return path if File.file?(path)

        raise_not_found_error
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
        File.file?(path) || File.file?(File.join(path, COVERAGE_FILE_NAME))
      end

      private def raise_ambiguous_coverage_file_error(expanded_pwd, expanded_root)
        raise ConfigurationError,
          "Ambiguous coverage file location specified. Both #{expanded_pwd} and #{expanded_root} exist. " \
          'Use `./` or an absolute filespec to disambiguate.'
      end

      private def raise_not_found_error
        message = "Could not find #{COVERAGE_FILE_NAME} under #{@root.inspect}; " \
                  'run tests or set --coverage-file option'
        CovLoupe.logger.error(message) if CovLoupe.logger
        raise CoverageFileNotFoundError, message
      end
    end
  end
end
