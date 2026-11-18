# frozen_string_literal: true

module CovLoupe
  # Valid CLI subcommands. Kept in its own file so startup option handling can use it
  # without loading the whole CLI.
  #
  # @api private
  SUBCOMMANDS = %w[list summary raw uncovered detailed totals validate].freeze

  # Optional single-character abbreviations for subcommands.
  #
  # @api private
  SUBCOMMAND_ABBREVIATIONS = {
    'd' => 'detailed',
    'l' => 'list',
    'r' => 'raw',
    's' => 'summary',
    't' => 'totals',
    'u' => 'uncovered',
    'v' => 'validate',
  }.freeze

  # Returns the subcommand a word names (resolving an abbreviation), or nil if it names none.
  #
  # @api private
  def self.subcommand_for(word)
    name = SUBCOMMAND_ABBREVIATIONS[word] || word
    SUBCOMMANDS.include?(name) ? name : nil
  end
end
