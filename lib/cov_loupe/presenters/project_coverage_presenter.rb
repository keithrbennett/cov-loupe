# frozen_string_literal: true

require_relative 'project_presenter'

require_relative '../staleness/stale_status'
require_relative '../staleness/root_mismatch'

module CovLoupe
  module Presenters
    # Presenter for project-wide coverage summaries (list/coverage table).
    #
    # Wraps CoverageModel#list, whose payload it returns unchanged, with accessors for the
    # CLI and MCP renderers.
    #
    # @api private
    class ProjectCoveragePresenter < ProjectPresenter
      attr_reader :sort_order

      def initialize(model:, sort_order:, raise_on_stale:, file_globs:)
        super(model: model, raise_on_stale: raise_on_stale, file_globs: file_globs)
        @sort_order = sort_order
      end

      # Returns the file rows rendered as the coverage table.
      def format_table(output_chars:)
        # The rows are already filtered by file_globs, so the table does not filter again.
        # (format_table uses raise_on_stale only when it builds the rows itself.)
        model.format_table(relative_files, sort_order: sort_order, file_globs: nil,
          output_chars: output_chars)
      end

      # Returns the project-relative file rows.
      def relative_files
        payload['files']
      end

      # Returns the project-relative skipped files.
      def relative_skipped_files
        payload['skipped_files']
      end

      # Returns the project-relative files that are not in coverage data.
      def relative_not_in_coverage_files
        payload['not_in_coverage_files']
      end

      # Returns the project-relative newer files.
      def relative_newer_files
        payload['newer_files']
      end

      # Returns the project-relative deleted files.
      def relative_deleted_files
        payload['deleted_files']
      end

      # Returns the project-relative length-mismatch files.
      def relative_length_mismatch_files
        payload['length_mismatch_files']
      end

      # Returns the project-relative unreadable files.
      def relative_unreadable_files
        payload['unreadable_files']
      end

      # Returns a warning when most files were not found under the project root, otherwise nil.
      # Counts only rows with coverage, as ProjectTotalsPresenter#root_warning does.
      def root_warning
        RootMismatch.message(
          deleted_count: relative_files.count { |row| row['stale'] == StaleStatus::DELETED },
          total_count:   relative_files.length,
          root:          model.root
        ) { model.recorded_root }
      end

      private def compute_payload
        model.list(
          sort_order:     sort_order,
          raise_on_stale: raise_on_stale,
          file_globs:     file_globs
        )
      end
    end
  end
end
