# frozen_string_literal: true

require_relative 'base_command'
require_relative '../presenters/project_coverage_presenter'
require_relative '../formatters/coverage_warnings'

module CovLoupe
  module Commands
    # @api private
    class ListCommand < BaseCommand
      def execute(args)
        reject_extra_args(args, 'list')

        presenter = Presenters::ProjectCoveragePresenter.new(
          model:          model,
          sort_order:     config.sort_order,
          raise_on_stale: config.raise_on_stale,
          file_globs:     config.file_globs
        )

        if maybe_output_structured_format?(presenter.payload)
          warn_nonempty(Formatters::CoverageWarnings.skipped_rows_warning(presenter))
        else
          puts model.format_table(
            presenter.relative_files,
            sort_order:     config.sort_order,
            raise_on_stale: config.raise_on_stale,
            file_globs:     nil,
            output_chars:   config.output_chars
          )
          # The exclusions summary already lists skipped rows.
          warn_nonempty(Formatters::CoverageWarnings.exclusions_summary(presenter))
        end

        warn_nonempty(
          Formatters::CoverageWarnings.timestamp_warning(presenter),
          Formatters::CoverageWarnings.root_warning(presenter)
        )
      end
    end
  end
end
