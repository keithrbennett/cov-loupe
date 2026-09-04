# frozen_string_literal: true

require_relative '../deprecation'
require_relative 'coverage_file_path_resolver'
require_relative 'coverage_line_resolver'

module CovLoupe
  module Resolvers
    # Facade that provides a single entry point for creating and using resolvers.
    # Delegates to CoverageFilePathResolver (file discovery) and CoverageLineResolver
    # (coverage lookup). This keeps resolver creation details out of client code.
    class ResolverHelpers
      def self.create_coverage_file_resolver(root: Dir.pwd, candidates: nil)
        candidates ?
          CoverageFilePathResolver.new(root: root, candidates: candidates) :
          CoverageFilePathResolver.new(root: root)
      end

      # Deprecated name for create_coverage_file_resolver. Removed in v7.0.0.
      def self.create_resultset_resolver(root: Dir.pwd, resultset: nil, candidates: nil)
        Deprecation.warn('ResolverHelpers.create_resultset_resolver',
          '.create_coverage_file_resolver')
        create_coverage_file_resolver(root: root, candidates: candidates)
      end

      def self.create_coverage_resolver(cov_data, root:, volume_case_sensitive:)
        CoverageLineResolver.new(cov_data, root: root, volume_case_sensitive: volume_case_sensitive)
      end

      def self.find_coverage_file(root, coverage_file: nil)
        CoverageFilePathResolver.new(root: root).find_coverage_file(coverage_file: coverage_file)
      end

      # Deprecated name for find_coverage_file. Removed in v7.0.0.
      def self.find_resultset(root, resultset: nil)
        Deprecation.warn('ResolverHelpers.find_resultset', '.find_coverage_file')
        find_coverage_file(root, coverage_file: resultset)
      end

      def self.lookup_lines(cov, file_abs, root:, volume_case_sensitive:)
        CoverageLineResolver.new(cov, root: root,
          volume_case_sensitive: volume_case_sensitive).lookup_lines(file_abs)
      end
    end
  end
end
