# frozen_string_literal: true

module CovLoupe
  # Valid CLI subcommands. Kept in its own file so startup option-error handling can use it
  # without loading the whole CLI.
  SUBCOMMANDS = %w[list summary raw uncovered detailed totals validate].freeze
end
