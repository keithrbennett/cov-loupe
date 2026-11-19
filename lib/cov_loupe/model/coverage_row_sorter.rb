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
    SORT_ORDERS = %i[ascending descending].freeze
    private_constant :SORT_ORDERS

    # @param rows [Array<Hash>] rows with 'file' and 'percentage' keys
    # @param sort_order [Symbol] :ascending or :descending
    # @param root [String] project root used to expand relative row paths
    # @return [Array<Hash>] a new sorted array
    # @raise [ArgumentError] if sort_order is not :ascending or :descending
    module_function def sort(rows, sort_order:, root:)
      validate_sort_order!(sort_order)
      descending = sort_order == :descending
      rows.sort_by do |row|
        percentage = row['percentage'] || Float::INFINITY
        [descending ? -percentage : percentage, PathUtils.expand_from_root(row['file'], root)]
      end
    end

    # @param sort_order [Object] the value to check
    # @return [void]
    # @raise [ArgumentError] if sort_order is not :ascending or :descending
    module_function def validate_sort_order!(sort_order)
      return if SORT_ORDERS.include?(sort_order)

      raise ArgumentError, "Invalid sort_order: #{sort_order.inspect}; expected :ascending or :descending"
    end
  end
end
