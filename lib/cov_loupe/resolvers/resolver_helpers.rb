# frozen_string_literal: true

require_relative 'coverage_file_path_resolver'
require_relative 'coverage_line_resolver'

module CovLoupe
  module Resolvers
    # Facade that provides a single entry point for creating and using resolvers.
    # Delegates to CoverageFilePathResolver (file discovery) and CoverageLineResolver
    # (coverage lookup). This keeps resolver creation details out of client code.
    class ResolverHelpers
      def self.create_coverage_resolver(cov_data, root:, volume_case_sensitive:)
        CoverageLineResolver.new(cov_data, root: root, volume_case_sensitive: volume_case_sensitive)
      end

      def self.find_coverage_file(root, coverage_file: nil)
        CoverageFilePathResolver.new(root: root).find_coverage_file(coverage_file: coverage_file)
      end

      def self.lookup_lines(cov, file_abs, root:, volume_case_sensitive:)
        CoverageLineResolver.new(cov, root: root,
          volume_case_sensitive: volume_case_sensitive).lookup_lines(file_abs)
      end
    end
  end
end
