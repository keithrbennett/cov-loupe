# frozen_string_literal: true

require_relative '../paths/path_utils'

module CovLoupe
  # Sorts coverage rows by percentage, breaking ties by absolute path so that rows with
  # project-relative paths sort the same way as the absolute rows used internally.
  #
  # Rows without a percentage (files with no coverable lines) rank above 100%, so they
  # come first in descending order and last in ascending order.
  #
  # @api private
  module CoverageRowSorter
    # @param rows [Array<Hash>] rows with 'file' and 'percentage' keys
    # @param sort_order [Symbol] :descending, or anything else for ascending
    # @param root [String] project root used to expand relative row paths
    # @return [Array<Hash>] a new sorted array
    module_function def sort(rows, sort_order:, root:)
      descending = sort_order == :descending
      rows.sort_by do |row|
        percentage = row['percentage'] || Float::INFINITY
        [descending ? -percentage : percentage, PathUtils.expand_from_root(row['file'], root)]
      end
    end
  end
end
