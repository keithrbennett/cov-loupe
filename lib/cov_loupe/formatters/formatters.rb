# frozen_string_literal: true

require 'stringio'
require_relative '../output_chars'

module CovLoupe
  # @api private
  module Formatters
    # Multi-format output dispatcher for coverage data.
    #
    # Supports JSON, pretty JSON, YAML, Amazing Print, inspect, puts, pretty_print,
    # and table formats. Optional format dependencies are loaded only when needed.
    # In ASCII mode (output_chars), JSON escapes non-ASCII characters as \uXXXX; other formats
    # keep the data as it is.
    #
    # The :table format is handled separately by CoverageTableFormatter and is
    # passed through here unchanged (table formatting happens at the command level).

    # Registry of format lambdas.
    # Each lambda receives the object to format and an ascii_mode keyword; only JSON uses it.
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
      yaml:          ->(obj, **) {
        require 'yaml'
        obj.to_yaml
      },
      amazing_print: ->(obj, **) {
        require 'amazing_print'
        obj.ai
      },
      inspect:       ->(obj, **) { obj.inspect },
      puts:          ->(obj, **) {
        sio = StringIO.new
        sio.puts(obj)
        sio.string
      },
      pretty_print:  ->(obj, **) {
        require 'pp'
        sio = StringIO.new
        PP.pp(obj, sio)
        sio.string
      },
    }.freeze

    # Formats an object using the specified format.
    #
    # @param obj [Object] The object to format
    # @param format [Symbol] Format type (:table, :json, :pretty_json, :yaml, :amazing_print,
    #   :inspect, :puts, :pretty_print)
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
