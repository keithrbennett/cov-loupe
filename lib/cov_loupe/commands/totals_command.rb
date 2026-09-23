# frozen_string_literal: true

require_relative 'base_command'
require_relative '../presenters/project_totals_presenter'
require_relative '../formatters/coverage_warnings'

module CovLoupe
  module Commands
    class TotalsCommand < BaseCommand
      def execute(args)
        reject_extra_args(args, 'totals')

        presenter = Presenters::ProjectTotalsPresenter.new(
          model:          model,
          raise_on_stale: config.raise_on_stale,
          tracked_globs:  config.tracked_globs
        )
        payload = presenter.absolute_payload
        return if maybe_output_structured_format?(payload, model)

        lines = payload['lines']
        files = payload['files']
        tracking = payload['tracking']
        with_coverage = files['with_coverage']
        without_coverage = files['without_coverage']

        if tracking && tracking['enabled']
          puts 'Tracked globs:'
          tracking['globs'].each { |glob| puts "  - #{convert_text(glob)}" }
        else
          puts 'Tracked globs: (tracking disabled)'
        end
        puts

        percent_display = lines['percentage'].nil? ? 'n/a' : format('%.2f%%', lines['percentage'])
        puts "Lines (#{lines['included_files']} ok files): " \
          "#{lines['total']} total, #{lines['covered']} covered, " \
          "#{lines['uncovered']} uncovered (#{percent_display})"
        with_coverage_line = format_with_coverage_line(with_coverage)
        stale_line = format_stale_breakdown(with_coverage['stale']['by_type'])
        without_coverage_line, without_breakdown_line =
          format_without_coverage_lines(without_coverage)

        puts <<~BREAKDOWN

          File breakdown:
          #{with_coverage_line}
          #{stale_line}
          #{without_coverage_line}
          #{without_breakdown_line}
        BREAKDOWN

        text = Formatters::CoverageWarnings.timestamp_warning(presenter)
        warn text unless text.empty?
      end

      private def format_with_coverage_line(with_coverage)
        stale = with_coverage['stale']
        "  With coverage: #{with_coverage['total']} total, #{with_coverage['ok']} ok, #{stale['total']} stale"
      end

      private def format_stale_breakdown(stale_by_type)
        '    Stale: missing on disk = ' \
          "#{stale_by_type[StaleStatus::MISSING_FROM_DISK]}, " \
          "newer than coverage = #{stale_by_type[StaleStatus::NEWER]}, " \
          "line mismatch = #{stale_by_type[StaleStatus::LENGTH_MISMATCH]}, " \
          "unreadable = #{stale_by_type[StaleStatus::UNREADABLE]}"
      end

      private def format_without_coverage_lines(without_coverage)
        return [nil, nil] unless without_coverage

        without_by_type = without_coverage['by_type']
        without_coverage_line = "  Without coverage: #{without_coverage['total']} total"
        without_breakdown_line = '    Missing from coverage = ' \
          "#{without_by_type[StaleStatus::MISSING_FROM_COVERAGE]}, " \
          "unreadable = #{without_by_type[StaleStatus::UNREADABLE]}, " \
          "skipped (errors) = #{without_by_type[StaleStatus::SKIPPED]}"
        [without_coverage_line, without_breakdown_line]
      end
    end
  end
end
