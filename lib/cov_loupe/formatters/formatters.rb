# frozen_string_literal: true

require_relative '../output_chars'

module CovLoupe
  module Formatters
    # Multi-format output dispatcher for coverage data.
    #
    # Supports JSON, pretty JSON, YAML, Amazing Print, and table formats.
    # Optional format dependencies are loaded only when needed.
    # ASCII-only output can be requested through output_chars.
    #
    # The :table format is handled separately by CoverageTableFormatter and is
    # passed through here unchanged (table formatting happens at the command level).

    # Registry of format lambdas.
    # Each lambda receives the object to format and an ascii_mode keyword.
    FORMATTERS = {
      table:         ->(obj, **) { obj },
      json:          ->(obj, ascii_mode:) {
        require 'json'
        ascii_mode ? JSON.generate(obj, ascii_only: true) : obj.to_json
      },
      pretty_json:   ->(obj, ascii_mode:) {
        require 'json'
        ascii_mode ? JSON.pretty_generate(obj, ascii_only: true) : JSON.pretty_generate(obj)
      },
      yaml:          ->(obj, ascii_mode:) {
        require 'yaml'
        yaml = obj.to_yaml
        ascii_mode ? OutputChars.convert(yaml, :ascii) : yaml
      },
      amazing_print: ->(obj, ascii_mode:) {
        require 'amazing_print'
        result = obj.ai
        ascii_mode ? OutputChars.convert(result, :ascii) : result
      },
    }.freeze

    # Formats an object using the specified format.
    #
    # @param obj [Object] The object to format
    # @param format [Symbol] Format type (:table, :json, :pretty_json, :yaml, :amazing_print)
    # @param output_chars [Symbol] Output character mode (:default, :fancy, :ascii)
    # @return [String] Formatted output
    def self.format(obj, format, output_chars: :default)
      formatter = FORMATTERS.fetch(format) { raise ArgumentError, "Unknown format: #{format}" }

      ascii_mode = OutputChars.ascii_mode?(output_chars)
      formatter.call(obj, ascii_mode: ascii_mode)
    rescue LoadError => e
      gem_name = e.message[/-- (\S+)/, 1] || 'required gem'
      raise LoadError, "The #{format} format requires the '#{gem_name}' gem. " \
                       "Install it with: gem install #{gem_name}"
    end
  end
end
