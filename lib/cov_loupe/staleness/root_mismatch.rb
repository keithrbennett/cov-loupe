# frozen_string_literal: true

module CovLoupe
  # Detects the likely symptom of a wrong project root. Coverage keys are project-relative,
  # so under the wrong root most files look deleted even though nothing was removed.
  #
  # @api private
  module RootMismatch
    # Callers count only files with coverage rows (rows skipped as malformed are excluded),
    # scoped to the tracked globs when they are set.
    #
    # @return [String, nil] a warning when most files were not found, otherwise nil
    module_function def message(deleted_count:, total_count:, root:)
      return unless deleted_count * 2 > total_count

      "The project root may be wrong: most files with coverage rows (#{deleted_count} of " \
        "#{total_count}) were not found under #{root}. Set the root with --root (CLI) or the " \
        'root argument (MCP, Ruby).'
    end
  end
end
