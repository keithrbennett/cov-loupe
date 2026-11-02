# frozen_string_literal: true

require_relative '../coverage/coverage_calculator'
require_relative '../errors/errors'
require_relative '../resolvers/resolver_helpers'

module CovLoupe
  # Builds per-file list rows from a coverage map, keyed by absolute path.
  #
  # Entries whose lines cannot be read are skipped rather than raised, so a caller can
  # still check staleness for every file before deciding whether to raise the first error.
  #
  # @api private
  class ListRowBuilder
    # @!attribute [r] rows
    #   @return [Array<Hash>] 'file', 'covered', 'total', and 'percentage' per readable entry
    # @!attribute [r] lines_by_path
    #   @return [Hash{String => Array<Integer, nil>}] coverage lines per readable entry
    # @!attribute [r] errors
    #   @return [Hash{String => CovLoupe::Error}] error per skipped entry
    Result = Data.define(:rows, :lines_by_path, :errors) do
      # @return [Array<Hash>] 'file', 'error', and 'error_class' per skipped entry
      def skipped_rows
        errors.map do |path, error|
          { 'file' => path, 'error' => error.message, 'error_class' => error.class.name }
        end
      end
    end

    # Extracts coverage lines from a SimpleCov entry.
    # Returns nil if the entry is not a Hash, has no lines array, or contains elements
    # other than Integer or nil; callers then fall back to the resolver, which validates
    # centrally and raises CoverageDataError with a detailed message.
    #
    # @param entry [Hash, Object] coverage entry from the coverage file
    # @param logger [CovLoupe::Logger]
    # @return [Array<Integer, nil>, nil]
    def self.lines_from_entry(entry, logger:)
      return unless entry.is_a?(Hash)

      lines = entry['lines']
      unless lines.is_a?(Array)
        logger.safe_log("Invalid coverage lines encountered (not an array): #{lines.class}") if lines
        return
      end

      lines if lines.all? { |v| v.nil? || v.is_a?(Integer) }
    end

    def initialize(coverage_map, root:, volume_case_sensitive:, logger:)
      @coverage_map = coverage_map
      @root = root
      @volume_case_sensitive = volume_case_sensitive
      @logger = logger
    end

    # @return [Result]
    def build
      lines_by_path = {}
      errors = {}

      rows = @coverage_map.filter_map do |abs_path, entry|
        lines = lines_for(abs_path, entry)
        next unless lines

        lines_by_path[abs_path] = lines
        { 'file' => abs_path }.merge(CoverageCalculator.summary(lines))
      rescue FileError, CoverageDataError => e
        @logger.safe_log("Skipping coverage row for #{abs_path}: #{e.message}")
        errors[abs_path] = e
        nil
      end

      Result.new(rows: rows, lines_by_path: lines_by_path, errors: errors)
    end

    # Reads lines straight from the entry, avoiding an O(n) resolver scan per file; only
    # malformed entries go through the resolver.
    private def lines_for(abs_path, entry)
      self.class.lines_from_entry(entry, logger: @logger) ||
        Resolvers::ResolverHelpers.lookup_lines(@coverage_map, abs_path, root: @root,
          volume_case_sensitive: @volume_case_sensitive)
    end
  end
end
