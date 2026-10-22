# frozen_string_literal: true

require_relative '../output_chars'

module CovLoupe
  # General-purpose table formatter with Unicode box-drawing or ASCII characters.
  #
  # Used by CLI subcommands (summary, raw, uncovered, detailed) to format
  # per-file data as aligned tables. Column widths are computed from content.
  # Supports horizontal alignment per column (left, right, center).
  #
  # @api private
  class TableFormatter
    # Format data as a table with box-drawing or ASCII characters.
    # @param headers [Array<String>] Column headers
    # @param rows [Array<Array>] Data rows (each row is an array of cell values)
    # @param alignments [Array<Symbol>] Column alignments (:left, :right, :center)
    # @param output_chars [Symbol] Output character mode (:default, :fancy, or :ascii)
    # @return [String] Formatted table
    def self.format(headers:, rows:, alignments: nil, output_chars: :default)
      return 'No data to display' if rows.empty?

      # Resolve mode and get appropriate charset
      resolved_mode = OutputChars.resolve_mode(output_chars)
      charset = OutputChars.charset_for(resolved_mode)

      alignments ||= [:left] * headers.size
      header_cells = headers.map(&:to_s)
      row_cells = rows.map { |row| row.map(&:to_s) }
      all_rows = [header_cells] + row_cells

      # Calculate column widths
      widths = headers.size.times.map do |col|
        all_rows.map { |row| row[col].to_s.length }.max
      end

      lines = []
      lines << border_line(widths, charset[:top_left], charset[:top_tee], charset[:top_right], charset)
      lines << data_row(header_cells, widths, alignments, charset)
      lines << border_line(widths, charset[:left_tee], charset[:cross], charset[:right_tee], charset)
      row_cells.each { |row| lines << data_row(row, widths, alignments, charset) }
      lines << border_line(widths, charset[:bottom_left], charset[:bottom_tee], charset[:bottom_right],
        charset)

      lines.join("\n")
    end

    # Format a single key-value table (vertical layout)
    # @param data [Hash] Key-value pairs
    # @param output_chars [Symbol] Output character mode (:default, :fancy, or :ascii)
    # @return [String] Formatted table
    def self.format_vertical(data, output_chars: :default)
      rows = data.map { |k, v| [k.to_s, v.to_s] }
      format(headers: %w[Key Value], rows: rows, alignments: %i[left left], output_chars: output_chars)
    end

    private_class_method def self.border_line(widths, left, mid, right, charset)
      h = charset[:horizontal]
      segments = widths.map { |w| h * (w + 2) }
      left + segments.join(mid) + right
    end

    private_class_method def self.data_row(cells, widths, alignments, charset)
      v = charset[:vertical]
      formatted = cells.each_with_index.map do |cell, i|
        align_cell(cell.to_s, widths[i], alignments[i])
      end
      "#{v} #{formatted.join(" #{v} ")} #{v}"
    end

    private_class_method def self.align_cell(content, width, alignment)
      case alignment
      when :right
        content.rjust(width)
      when :center
        content.center(width)
      else # :left
        content.ljust(width)
      end
    end
  end
end
