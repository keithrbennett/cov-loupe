# frozen_string_literal: true

require_relative '../paths/path_utils'

module CovLoupe
  # Detects the likely symptom of a wrong project root. Coverage keys are project-relative,
  # so under the wrong root most files look deleted even though nothing was removed.
  #
  # @api private
  module RootMismatch
    # Callers count only files with coverage rows (rows skipped as malformed are excluded),
    # scoped to the tracked globs when they are set.
    #
    # The block returns meta.root from coverage.json; it is called only when the
    # warning fires. That root is suggested only when it differs from root and is a directory
    # here; coverage generated on another machine records a path that is not.
    #
    # @return [String, nil] a warning when most files were not found, otherwise nil
    module_function def message(deleted_count:, total_count:, root:)
      return unless deleted_count * 2 > total_count

      message = "The project root may be wrong: most files with coverage rows (#{deleted_count} of " \
                "#{total_count}) were not found under #{root}. Set the root with --root (CLI) or the " \
                'root argument (MCP, Ruby).'
      suggestion = suggested_root(root, yield)
      suggestion ? "#{message} The coverage file was generated with root #{suggestion}." : message
    end

    module_function def suggested_root(root, recorded_root)
      return unless recorded_root

      recorded = PathUtils.expand(recorded_root)
      recorded if recorded != PathUtils.expand(root) && File.directory?(recorded)
    end
    private_class_method :suggested_root
  end
end
