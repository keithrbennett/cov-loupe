# frozen_string_literal: true

require_relative '../output_chars'

module CovLoupe
  # Formats staleness error messages with human-readable timestamps and file lists.
  #
  # Used by CoverageDataStaleError and CoverageDataProjectStaleError to produce
  # consistent, detailed diagnostics. Includes UTC and local times for both
  # coverage generation and source file modification, plus the delta in seconds.
  #
  # File lists are capped at 10 entries to keep error messages readable.
  class StalenessMessageFormatter
    def initialize(cov_timestamp:, coverage_file_path: nil, output_chars: :default)
      @cov_timestamp = cov_timestamp
      @coverage_file_path = coverage_file_path
      @output_chars = output_chars
    end

    def format_project_details(newer_files:, missing_files:, deleted_files:,
      length_mismatch_files:, unreadable_files: [])
      [
        format_coverage_time,
        *format_file_list(newer_files, 'Newer files'),
        *format_file_list(missing_files, 'Missing files', 'new in project, not in coverage'),
        *format_file_list(deleted_files, 'Coverage-only files', 'deleted or moved in project'),
        *format_file_list(length_mismatch_files, 'Line count mismatches'),
        *format_file_list(unreadable_files, 'Unreadable files', 'permission denied or read errors'),
        (@coverage_file_path ? "\nResultset - #{convert_path(@coverage_file_path)}" : nil),
      ].compact.join
    end

    def format_single_file_details(file_path:, file_mtime:, src_len:, cov_len:)
      file_utc, file_local = format_time_both(file_mtime)
      cov_utc, cov_local = format_epoch_both(@cov_timestamp)
      delta_str = format_delta_seconds(file_mtime, @cov_timestamp)

      details = <<~DETAILS

        File     - time: #{file_utc || 'not found'} (local #{file_local || 'n/a'}), lines: #{src_len}
        Coverage - time: #{cov_utc  || 'not found'} (local #{cov_local  || 'n/a'}), lines: #{cov_len}
        DETAILS

      details += "\nDelta    - file is #{delta_str} newer than coverage" if delta_str
      details += "\nResultset - #{convert_path(@coverage_file_path)}" if @coverage_file_path
      details.chomp
    end

    private def convert_path(path)
      OutputChars.convert(path, @output_chars)
    end

    private def format_coverage_time
      cov_utc, cov_local = format_epoch_both(@cov_timestamp)
      "\nCoverage  - time: #{cov_utc || 'not found'} (local #{cov_local || 'n/a'})"
    end

    private def format_file_list(files, label, description = nil)
      return [] if files.empty?

      desc = description ? " (#{description}, #{files.size}):" : " (#{files.size}):"
      [
        "\n#{label}#{desc}",
        *files.first(10).map { |f| "  - #{convert_path(f)}" },
        *(files.size > 10 ? ['  ...'] : []),
      ]
    end

    private def format_epoch_both(epoch_seconds)
      return [nil, nil] unless epoch_seconds

      t = Time.at(epoch_seconds.to_i)
      [t.utc.iso8601, t.getlocal.iso8601]
    rescue
      [epoch_seconds.to_s, epoch_seconds.to_s]
    end

    private def format_time_both(time)
      return [nil, nil] unless time

      t = time.is_a?(Time) ? time : Time.parse(time.to_s)
      [t.utc.iso8601, t.getlocal.iso8601]
    rescue
      [time.to_s, time.to_s]
    end

    private def format_delta_seconds(file_mtime, cov_timestamp)
      return nil unless file_mtime && cov_timestamp

      seconds = file_mtime.to_i - cov_timestamp.to_i
      sign = seconds >= 0 ? '+' : '-'
      "#{sign}#{seconds.abs}s"
    rescue
      nil
    end
  end
end
