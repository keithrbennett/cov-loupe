# frozen_string_literal: true

module CovLoupe
  # Shared normalization logic for CLI and MCP tool options.
  #
  # Provides two modes for each normalizer:
  #   - strict: true  → raise OptionParser::InvalidArgument on invalid values
  #   - strict: false → return a default value (nil or specified default) on invalid values
  #
  # All normalizers accept both full names and single-character abbreviations.
  module OptionNormalizers
    SORT_ORDER_MAP = {
      'a'          => :ascending,
      'ascending'  => :ascending,
      'd'          => :descending,
      'descending' => :descending,
    }.freeze

    SOURCE_MODE_MAP = {
      'n'         => :none,
      'none'      => :none,
      'f'         => :full,
      'full'      => :full,
      'u'         => :uncovered,
      'uncovered' => :uncovered,
    }.freeze

    ERROR_MODE_MAP = {
      'off'   => :off,
      'o'     => :off,
      'log'   => :log,
      'l'     => :log,
      'debug' => :debug,
      'd'     => :debug,
    }.freeze

    # Canonical short codes and their single canonical long name.
    # Codes are case-sensitive (e.g. 'j' => json, 'J' => pretty_json) so both
    # are looked up via exact match before any case-insensitive fallback.
    FORMAT_MAP = {
      'a'             => :amazing_print,
      'amazing_print' => :amazing_print,
      'i'             => :inspect,
      'inspect'       => :inspect,
      'j'             => :json,
      'json'          => :json,
      'J'             => :pretty_json,
      'pretty_json'   => :pretty_json,
      'p'             => :puts,
      'puts'          => :puts,
      'P'             => :pretty_print,
      'pretty_print'  => :pretty_print,
      't'             => :table,
      'table'         => :table,
      'y'             => :yaml,
      'yaml'          => :yaml,
    }.freeze

    MODE_MAP = {
      'cli' => :cli,
      'c'   => :cli,
      'mcp' => :mcp,
      'm'   => :mcp,
    }.freeze

    OUTPUT_CHARS_MAP = {
      'd'       => :default,
      'default' => :default,
      'f'       => :fancy,
      'fancy'   => :fancy,
      'a'       => :ascii,
      'ascii'   => :ascii,
    }.freeze

    module_function def normalize_sort_order(value, strict: true)
      normalized = SORT_ORDER_MAP[value.to_s.downcase]
      return normalized if normalized
      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      nil
    end

    # Normalize source mode value.
    # @param value [String, Symbol, nil] The value to normalize
    # @param strict [Boolean] If true, raises on invalid value; if false, returns nil
    # @return [Symbol, nil] The normalized symbol or nil if invalid and not strict
    # @raise [OptionParser::InvalidArgument] If strict and value is invalid
    module_function def normalize_source_mode(value, strict: true)
      normalized = SOURCE_MODE_MAP[value.to_s.downcase]
      return nil if normalized == :none
      return normalized if normalized
      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      nil
    end

    # Normalize error mode value.
    # @param value [String, Symbol, nil] The value to normalize
    # @param strict [Boolean] If true, raises on invalid value; if false, returns default
    # @param default [Symbol] The default value to return if invalid and not strict
    # @return [Symbol] The normalized symbol or default if invalid and not strict
    # @raise [OptionParser::InvalidArgument] If strict and value is invalid
    module_function def normalize_error_mode(value, strict: true, default: :log)
      normalized = ERROR_MODE_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      default
    end

    # Normalize format value.
    # @param value [String, Symbol] The value to normalize
    # @param strict [Boolean] If true, raises on invalid value; if false, returns nil
    # @return [Symbol, nil] The normalized symbol or nil if invalid and not strict
    # @raise [OptionParser::InvalidArgument] If strict and value is invalid
    module_function def normalize_format(value, strict: true)
      normalized = FORMAT_MAP[value.to_s]
      return normalized if normalized

      # Only allow case-insensitive match for multi-character keys
      # to avoid single-char shortcuts like 'J' falling through to 'j'
      if value.to_s.length == 1
        raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

        return nil
      end

      normalized = FORMAT_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      nil
    end

    # Normalize mode value (cli or mcp).
    # @param value [String, Symbol] The value to normalize
    # @param strict [Boolean] If true, raises on invalid value; if false, returns default
    # @param default [Symbol] The default value to return if invalid and not strict
    # @return [Symbol] The normalized symbol (:cli or :mcp)
    # @raise [OptionParser::InvalidArgument] If strict and value is invalid
    module_function def normalize_mode(value, strict: true, default: :cli)
      normalized = MODE_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      default
    end

    # Normalize output_chars value.
    # Controls ASCII vs Unicode (fancy) output for tables and text.
    # @param value [String, Symbol] The value to normalize
    # @param strict [Boolean] If true, raises on invalid value; if false, returns default
    # @param default [Symbol] The default value to return if invalid and not strict
    # @return [Symbol] The normalized symbol (:default, :fancy, or :ascii)
    # @raise [OptionParser::InvalidArgument] If strict and value is invalid
    module_function def normalize_output_chars(value, strict: true, default: :default)
      normalized = OUTPUT_CHARS_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, "invalid argument: #{value}" if strict

      default
    end
  end
end
