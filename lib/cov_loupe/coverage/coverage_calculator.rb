# frozen_string_literal: true

module CovLoupe
  # Provides coverage data transformations and calculations.
  # All methods are pure functions that operate on SimpleCov line coverage arrays.
  #
  # SimpleCov line coverage array convention:
  #   - Integer → coverable line with hit count (0 = uncovered, >0 = covered)
  #   - nil     → non-code line (not counted in totals)
  #
  # Line numbers in output are 1-indexed (matching editor display).
  class CoverageCalculator
    # Calculates coverage summary statistics from a coverage array.
    #
    # @param coverage_lines [Array<Integer, nil>] SimpleCov coverage array where each element
    #   represents a line: Integer for hit count, nil for non-code lines
    # @return [Hash] summary with 'covered', 'total', and 'percentage' keys
    def self.summary(coverage_lines)
      total = 0
      covered = 0
      coverage_lines.compact.each do |hits|
        total += 1
        covered += 1 if hits.to_i > 0
      end
      percentage = truncated_percentage(covered, total)
      { 'covered' => covered, 'total' => total, 'percentage' => percentage }
    end

    # Identifies uncovered line numbers from a coverage array.
    #
    # @param coverage_lines [Array<Integer, nil>] SimpleCov coverage array
    # @return [Array<Integer>] array of uncovered line numbers (1-indexed)
    def self.uncovered(coverage_lines)
      out = []

      coverage_lines.each_with_index do |hits, i|
        next if hits.nil?

        out << (i + 1) if hits.to_i.zero?
      end
      out
    end

    # Generates detailed line-by-line coverage information.
    #
    # @param coverage_lines [Array<Integer, nil>] SimpleCov coverage array
    # @return [Array<Hash>] array of hashes with 'line', 'hits', and 'covered' keys
    def self.detailed(coverage_lines)
      rows = []
      coverage_lines.each_with_index do |hits, i|
        next if hits.nil?

        h = hits.to_i
        rows << { 'line' => i + 1, 'hits' => h, 'covered' => h.positive? }
      end
      rows
    end

    # Aggregates coverage summaries from multiple files.
    #
    # @param file_summaries [Array<Hash>] array of hashes with 'covered' and 'total' keys
    # @return [Hash] aggregated summary with 'covered', 'uncovered', 'total', and 'percentage' keys
    def self.aggregate(file_summaries)
      covered = file_summaries.sum { |row| row['covered'].to_i }
      total = file_summaries.sum { |row| row['total'].to_i }
      uncovered = total - covered
      percentage = truncated_percentage(covered, total)

      {
        'covered'    => covered,
        'uncovered'  => uncovered,
        'total'      => total,
        'percentage' => percentage,
      }
    end

    # Truncates (rather than rounds) to two decimals so incomplete coverage never reports 100.0.
    # Integer arithmetic avoids float error before the final division.
    #
    # @return [Float, nil] percentage, or nil when there are no coverable lines
    def self.truncated_percentage(covered, total)
      return nil if total <= 0

      (covered * 10_000 / total) / 100.0
    end
    private_class_method :truncated_percentage
  end
end
