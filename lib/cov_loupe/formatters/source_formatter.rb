# frozen_string_literal: true

require_relative '../output_chars'

module CovLoupe
  module Formatters
    # Formats source code with inline coverage markers for CLI output.
    #
    # Supports two display modes:
    #   - :full      → show all lines with coverage markers
    #   - :uncovered → show only uncovered lines with N lines of context around each
    #
    # Covered and uncovered lines are marked in the output, with optional ANSI
    # color coding. The context value controls how many surrounding lines are
    # shown in :uncovered mode.
    class SourceFormatter
      def initialize(color_enabled: true, output_chars: :default)
        @color_enabled = color_enabled
        @output_chars = output_chars
      end

      def format_source_for(model, path, mode: nil, context: 2)
        raw = fetch_raw(model, path)
        return '[source not available]' unless raw

        abs = raw['file']
        lines_cov = raw['lines']
        src = File.file?(abs) ? File.readlines(abs, chomp: true) : nil
        return '[source not available]' unless src

        begin
          rows = build_source_rows(src, lines_cov, mode: mode, context: context)
          format_source_rows(rows)
        rescue ArgumentError
          raise
        rescue => e
          # If any unexpected formatting/indexing error occurs, avoid crashing the CLI
          CovLoupe.logger.safe_log(
            "SourceFormatter#format_source_for error for path '#{abs}': #{e.class} - #{e.message}")
          '[source not available]'
        end
      end

      def build_source_payload(model, path, mode: nil, context: 2)
        raw = fetch_raw(model, path)
        return nil unless raw

        abs = raw['file']
        lines_cov = raw['lines']
        src = File.file?(abs) ? File.readlines(abs, chomp: true) : nil
        return nil unless src

        build_source_rows(src, lines_cov, mode: mode, context: context)
      end

      def build_source_rows(src_lines, cov_lines, mode:, context: 2)
        # Normalize inputs defensively to avoid type errors in formatting
        coverage_lines = cov_lines || []
        context_line_count = begin
          context.to_i
        rescue
          2
        end
        raise ArgumentError, 'Context lines cannot be negative' if context_line_count.negative?

        n = src_lines.length
        include_line = Array.new(n, mode == :full)
        if mode == :uncovered
          include_line = mark_uncovered_lines_with_context(coverage_lines, context_line_count, n)
        end

        build_row_data(src_lines, coverage_lines, include_line)
      end

      def format_source_rows(rows)
        # Use ASCII-safe markers when output_chars is :ascii
        check_mark = OutputChars.ascii_mode?(@output_chars) ? '+' : "\u2713"
        miss_mark = 'X'

        marker = ->(covered, _hits) do
          case covered
          when true then colorize(check_mark, :green)
          when false then colorize(miss_mark, :red)
          else colorize(' ', :dim)
          end
        end

        hyphen_line = format('%6s-%2s-+-%s', '------', '--', '-' * 60)

        lines = [
          '',
          hyphen_line,
          format('%6s %2s | %s', 'Line', ' ', 'Source'),
          hyphen_line,
        ]

        rows.each do |r|
          m = marker.call(r['covered'], r['hits'])
          # Convert source code to ASCII when in ASCII mode
          code = OutputChars.convert(r['code'], @output_chars)
          lines << format('%6d  %2s | %s', r['line'], m, code)
        end
        lines.join("\n")
      end

      attr_reader :color_enabled, :output_chars

      private def fetch_raw(model, path)
        @raw_cache ||= {}
        return @raw_cache[path] if @raw_cache.key?(path)

        raw = model.raw_for(path)
        @raw_cache[path] = raw
      rescue => e
        CovLoupe.logger.safe_log(
          "SourceFormatter#fetch_raw error for path '#{path}': #{e.class} - #{e.message}")
        nil
      end

      private def mark_uncovered_lines_with_context(coverage_lines, context_line_count, total_lines)
        include_line = Array.new(total_lines, false)
        misses = find_uncovered_lines(coverage_lines)

        misses.each do |uncovered_line_index|
          mark_context_lines(include_line, uncovered_line_index, context_line_count, total_lines)
        end

        include_line
      end

      private def find_uncovered_lines(coverage_lines)
        misses = []
        coverage_lines.each_with_index do |hits, i|
          misses << i if !hits.nil? && hits.to_i == 0
        end
        misses
      end

      private def mark_context_lines(include_line, center_line, context_count, total_lines)
        start_line = [0, center_line - context_count].max
        end_line = [total_lines - 1, center_line + context_count].min

        (start_line..end_line).each { |i| include_line[i] = true }
      end

      private def build_row_data(src_lines, coverage_lines, include_line)
        out = []
        src_lines.each_with_index do |code, i|
          next unless include_line[i]

          hits = coverage_lines[i]
          covered = hits.nil? ? nil : hits.to_i > 0
          # Use string keys consistently across CLI formatting and JSON payloads
          out << { 'line' => i + 1, 'code' => code, 'hits' => hits, 'covered' => covered }
        end
        out
      end

      private def colorize(text, color)
        return text unless color_enabled

        codes = { green: 32, red: 31, dim: 2 }
        code = codes[color] || 0
        "\e[#{code}m#{text}\e[0m"
      end
    end
  end
end
