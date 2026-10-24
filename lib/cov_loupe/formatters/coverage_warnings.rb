# frozen_string_literal: true

module CovLoupe
  module Formatters
    # Text renderings of project-coverage exclusions and warnings, shared by the CLI
    # (written to stderr) and the MCP project_coverage tool (appended to table output).
    # Each method takes a ProjectCoveragePresenter and returns a String ('' when there is
    # nothing to report).
    #
    # @api private
    module CoverageWarnings
      TIMESTAMP_WARNING_LINES = [
        'Coverage timestamps are missing. Time-based staleness checks were skipped.',
        'Files may appear "ok" even if source code is newer than the coverage data.',
        'Check your coverage tool configuration to ensure timestamps are recorded.',
      ].freeze

      EXCLUDED_FILE_SECTIONS = {
        relative_missing_tracked_files: 'Missing tracked files',
        relative_newer_files:           'Files newer than coverage',
        relative_deleted_files:         'Deleted files with coverage',
        relative_length_mismatch_files: 'Line count mismatches',
        relative_unreadable_files:      'Unreadable files',
      }.freeze

      module_function def exclusions_summary(presenter)
        sections = EXCLUDED_FILE_SECTIONS.map { |meth, header| [header, presenter.public_send(meth)] }
        skipped = presenter.relative_skipped_files
        return '' if sections.all? { |_, files| files.empty? } && skipped.empty?

        output = ["\nFiles excluded from coverage:"]
        sections.each do |header, files|
          next if files.empty?

          output << "\n#{header} (#{files.length}):"
          files.each { |file| output << "  - #{file}" }
        end

        unless skipped.empty?
          output << "\nFiles skipped due to errors (#{skipped.length}):"
          output.concat(skipped_row_lines(skipped))
        end

        output << "\nRun with --raise-on-stale true to exit when files are excluded."
        output.join("\n")
      end

      module_function def timestamp_warning(presenter)
        return '' unless presenter.timestamp_status == 'missing'

        "\nWARNING: #{TIMESTAMP_WARNING_LINES.join("\n")}\n"
      end

      module_function def skipped_rows_warning(presenter)
        skipped = presenter.relative_skipped_files
        return '' if skipped.nil? || skipped.empty?

        count = skipped.length
        output = ['', "WARNING: #{count} coverage row#{count == 1 ? '' : 's'} skipped due to errors:"]
        output.concat(skipped_row_lines(skipped))
        output << 'Run again with --raise-on-stale true to exit when rows are skipped.'
        output.join("\n")
      end

      module_function def skipped_row_lines(skipped)
        skipped.map { |row| "  - #{row['file']}: #{row['error']}" }
      end
    end
  end
end
