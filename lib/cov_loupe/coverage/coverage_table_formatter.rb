# frozen_string_literal: true

require_relative '../staleness/stale_status'
require_relative '../output_chars'

module CovLoupe
  # Formats coverage data as a table with Unicode box-drawing or ASCII borders.
  #
  # Used by CoverageModel#format_table for the default `cov-loupe list` output.
  # Column widths are computed dynamically from the data. The table includes:
  #   - File path from each row
  #   - Coverage percentage
  #   - Covered lines
  #   - Total lines
  #   - Staleness indicator
  #
  # A footer row summarizes file counts (total, ok, stale).
  #
  # @api private
  class CoverageTableFormatter
    # Format coverage rows as a table with box-drawing or ASCII characters.
    #
    # @param rows [Array<Hash>] Coverage rows with keys: 'file', 'percentage', 'covered', 'total', 'stale'
    # @param output_chars [Symbol] Output character mode (:default, :fancy, or :ascii)
    # @return [String] Formatted table with borders and summary
    def self.format(rows, output_chars: :default)
      return 'No coverage data found' if rows.empty?

      # Resolve mode and get appropriate charset
      resolved_mode = OutputChars.resolve_mode(output_chars)
      charset = OutputChars.charset_for(resolved_mode)

      widths = compute_table_widths(rows)
      lines = []
      lines << border_line(widths, charset[:top_left], charset[:top_tee], charset[:top_right], charset)
      lines << header_row(widths, charset)
      lines << border_line(widths, charset[:left_tee], charset[:cross], charset[:right_tee], charset)
      rows.each { |file_data| lines << data_row(file_data, widths, charset) }
      lines << border_line(widths, charset[:bottom_left], charset[:bottom_tee], charset[:bottom_right],
        charset)
      lines << summary_counts(rows)
      if rows.any? { |f| StaleStatus.stale?(f['stale']) }
        lines <<
          'Staleness: deleted, newer, length_mismatch, unreadable'
      end
      lines.join("\n")
    end

    # Calculate column widths based on data
    #
    # @param rows [Array<Hash>] Coverage rows
    # @return [Hash] Width for each column (:file, :pct, :covered, :total, :stale)
    private_class_method def self.compute_table_widths(rows)
      max_file_length = rows.map { |f| f['file'].length }.max.to_i
      file_width = [max_file_length, 'File'.length].max + 2
      pct_width = 8
      max_covered = rows.map { |f| f['covered'].to_s.length }.max
      max_total = rows.map { |f| f['total'].to_s.length }.max
      covered_width = [max_covered, 'Covered'.length].max + 2
      total_width = [max_total, 'Total'.length].max + 2
      max_stale_label = rows.map { |f| StaleStatus.stale?(f['stale']) ? f['stale'].to_s.length : 0 }.max.to_i
      stale_width = [max_stale_label, 'Stale'.length].max
      {
        file:    file_width,
        pct:     pct_width,
        covered: covered_width,
        total:   total_width,
        stale:   stale_width,
      }
    end

    # Generate a border line for the table
    #
    # @param widths [Hash] Column widths
    # @param left [String] Left edge character
    # @param middle [String] Column separator character
    # @param right [String] Right edge character
    # @param charset [Hash] Character set for borders
    # @return [String] Border line
    private_class_method def self.border_line(widths, left, middle, right, charset)
      h = charset[:horizontal]
      h_line = ->(col_width) { h * (col_width + 2) }
      left +
        h_line.call(widths[:file]) +
        middle + h_line.call(widths[:pct]) +
        middle + h_line.call(widths[:covered]) +
        middle + h_line.call(widths[:total]) +
        middle + h_line.call(widths[:stale]) +
        right
    end

    # Generate the header row
    #
    # @param widths [Hash] Column widths
    # @param charset [Hash] Character set for borders
    # @return [String] Header row
    private_class_method def self.header_row(widths, charset)
      v = charset[:vertical]
      Kernel.format(
        "#{v} %-#{widths[:file]}s #{v} %#{widths[:pct]}s #{v} %#{widths[:covered]}s " \
        "#{v} %#{widths[:total]}s #{v} %#{widths[:stale]}s #{v}",
        'File', ' %', 'Covered', 'Total', 'Stale'.center(widths[:stale])
      )
    end

    # Generate a data row for a single file
    #
    # @param file_data [Hash] Coverage data for one file
    # @param widths [Hash] Column widths
    # @param charset [Hash] Character set for borders
    # @return [String] Data row
    private_class_method def self.data_row(file_data, widths, charset)
      fd = file_data
      ws = widths
      v = charset[:vertical]
      is_stale = StaleStatus.stale?(fd['stale'])
      stale_str = is_stale ? fd['stale'].to_s.center(ws[:stale]) : ''
      pct_str = if fd['percentage']
        Kernel.format("%#{ws[:pct] - 1}.2f%%", fd['percentage'])
      else
        'n/a'.rjust(ws[:pct])
      end

      format_str =
        "#{v} %-#{ws[:file]}s #{v} %s #{v} %#{ws[:covered]}d #{v} %#{ws[:total]}d #{v} %#{ws[:stale]}s #{v}"
      Kernel.format(format_str, fd['file'], pct_str, fd['covered'], fd['total'], stale_str)
    end

    # Generate summary counts footer
    #
    # @param rows [Array<Hash>] Coverage rows
    # @return [String] Summary line
    private_class_method def self.summary_counts(rows)
      total = rows.length
      stale_count = rows.count { |f| StaleStatus.stale?(f['stale']) }
      ok_count = total - stale_count
      "Files: total #{total}, ok #{ok_count}, stale #{stale_count}"
    end
  end
end
