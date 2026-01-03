# frozen_string_literal: true

module CovLoupe
  # Formats coverage data as a table with box-drawing characters
  # Extracted from CoverageModel to separate presentation from domain logic
  class CoverageTableFormatter
    # Format coverage rows as a table with box-drawing characters
    #
    # @param rows [Array<Hash>] Coverage rows with keys: 'file', 'percentage', 'covered', 'total', 'stale'
    # @return [String] Formatted table with borders and summary
    def self.format(rows)
      return 'No coverage data found' if rows.empty?

      widths = compute_table_widths(rows)
      lines = []
      lines << border_line(widths, '┌', '┬', '┐')
      lines << header_row(widths)
      lines << border_line(widths, '├', '┼', '┤')
      rows.each { |file_data| lines << data_row(file_data, widths) }
      lines << border_line(widths, '└', '┴', '┘')
      lines << summary_counts(rows)
      if rows.any? { |f| f['stale'] }
        lines <<
          'Staleness: E = Error checking, M = Missing file, ' \
          'T = Timestamp (source newer), L = Line count mismatch'
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
      stale_width = 'Stale'.length
      {
        file: file_width,
        pct: pct_width,
        covered: covered_width,
        total: total_width,
        stale: stale_width
      }
    end

    # Generate a border line for the table
    #
    # @param widths [Hash] Column widths
    # @param left [String] Left edge character
    # @param middle [String] Column separator character
    # @param right [String] Right edge character
    # @return [String] Border line
    private_class_method def self.border_line(widths, left, middle, right)
      h_line = ->(col_width) { '─' * (col_width + 2) }
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
    # @return [String] Header row
    private_class_method def self.header_row(widths)
      Kernel.format(
        "│ %-#{widths[:file]}s │ %#{widths[:pct]}s │ %#{widths[:covered]}s │ %#{widths[:total]}s │ %#{widths[:stale]}s │",
        'File', ' %', 'Covered', 'Total', 'Stale'.center(widths[:stale])
      )
    end

    # Generate a data row for a single file
    #
    # @param file_data [Hash] Coverage data for one file
    # @param widths [Hash] Column widths
    # @return [String] Data row
    private_class_method def self.data_row(file_data, widths)
      stale_text_str = file_data['stale'] ? file_data['stale'].to_s : ''
      Kernel.format(
        "│ %-#{widths[:file]}s │ %#{widths[:pct] - 1}.2f%% │ %#{widths[:covered]}d │ %#{widths[:total]}d │ %#{widths[:stale]}s │",
        file_data['file'],
        file_data['percent_covered'],
        file_data['covered'],
        file_data['total'],
        stale_text_str.center(widths[:stale])
      )
    end

    # Generate summary counts footer
    #
    # @param rows [Array<Hash>] Coverage rows
    # @return [String] Summary line
    private_class_method def self.summary_counts(rows)
      total = rows.length
      stale_count = rows.count { |f| f['stale'] }
      ok_count = total - stale_count
      "Files: total #{total}, ok #{ok_count}, stale #{stale_count}"
    end
  end
end
