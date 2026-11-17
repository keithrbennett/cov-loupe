# frozen_string_literal: true

module CovLoupe
  # Shared normalization logic for CLI and MCP tool options. Each normalizer raises
  # OptionParser::InvalidArgument on an invalid value, with only the value as its argument.
  # The exception adds "invalid argument:"; when the value comes from an option handler,
  # OptionParser also adds the option (`--format bogus`) or, for `--format=bogus`, puts the
  # whole argument in place of the value.
  #
  # All normalizers accept both full names and single-character abbreviations.
  #
  # @api private
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

    # Canonical long format name -> canonical single-letter short code.
    # Insertion order is the display order used throughout help text, enums,
    # and error messages (a, i, j, J, p, P, t, y): alphabetical by downcased
    # code, with the lowercase member of a case pair (j/J, p/P) before the
    # uppercase one. `available_format_choices` and `resolve_format_code`
    # both rely on this order/content, so keep it as the single source of
    # truth when formats are added, renamed, or reordered.
    FORMAT_LONG_NAMES = {
      'amazing_print' => 'a',
      'inspect'       => 'i',
      'json'          => 'j',
      'pretty_json'   => 'J',
      'puts'          => 'p',
      'pretty_print'  => 'P',
      'table'         => 't',
      'yaml'          => 'y',
    }.freeze

    # Canonical single-letter short code -> canonical format symbol.
    # Codes are case-sensitive (e.g. 'j' => json, 'J' => pretty_json) so both
    # are looked up via exact match before any case-insensitive fallback.
    FORMAT_MAP = {
      'a' => :amazing_print,
      'i' => :inspect,
      'j' => :json,
      'J' => :pretty_json,
      'p' => :puts,
      'P' => :pretty_print,
      't' => :table,
      'y' => :yaml,
    }.freeze

    # Resolves a raw format value (a canonical long name, a short code, or
    # anything else) to a single-letter short code.
    #
    # Long names are looked up in FORMAT_LONG_NAMES and mapped to their code.
    # Everything else - an already-short code, a differently-cased variant,
    # or an unrecognized value - passes through unchanged; it is up to the
    # caller's FORMAT_MAP lookup to accept it (if it's a valid code) or
    # reject it (if it isn't).
    module_function def resolve_format_code(value)
      str = value.to_s
      FORMAT_LONG_NAMES.fetch(str, str)
    end

    # Returns "code/long_name" strings for every canonical format, in the
    # display order defined by FORMAT_LONG_NAMES.
    #
    # Iterates FORMAT_LONG_NAMES directly (rather than sorting its keys/values
    # with a comparator) because Ruby hashes preserve insertion order and
    # FORMAT_LONG_NAMES is already defined in the correct display order.
    module_function def available_format_choices
      FORMAT_LONG_NAMES.map { |long_name, code| "#{code}/#{long_name}" }
    end

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

    module_function def normalize_sort_order(value)
      normalized = SORT_ORDER_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end

    # Normalize source mode value.
    # @param value [String, Symbol] The value to normalize
    # @return [Symbol, nil] The normalized symbol, or nil for none
    # @raise [OptionParser::InvalidArgument] If value is invalid
    module_function def normalize_source_mode(value)
      normalized = SOURCE_MODE_MAP[value.to_s.downcase]
      return nil if normalized == :none
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end

    # Normalize error mode value.
    # @param value [String, Symbol] The value to normalize
    # @return [Symbol] The normalized symbol
    # @raise [OptionParser::InvalidArgument] If value is invalid
    module_function def normalize_error_mode(value)
      normalized = ERROR_MODE_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end

    # Normalize format value.
    # @param value [String, Symbol] The value to normalize
    # @return [Symbol] The normalized symbol
    # @raise [OptionParser::InvalidArgument] If value is invalid
    module_function def normalize_format(value)
      normalized = FORMAT_MAP[resolve_format_code(value)]
      return normalized if normalized

      # Only allow case-insensitive match for multi-character keys
      # to avoid single-char shortcuts like 'J' falling through to 'j'
      raise OptionParser::InvalidArgument, value.to_s if value.to_s.length == 1

      normalized = FORMAT_MAP[resolve_format_code(value.to_s.downcase)]
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end

    # Normalize mode value (cli or mcp).
    # @param value [String, Symbol] The value to normalize
    # @return [Symbol] The normalized symbol (:cli or :mcp)
    # @raise [OptionParser::InvalidArgument] If value is invalid
    module_function def normalize_mode(value)
      normalized = MODE_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end

    # Normalize output_chars value.
    # Chooses Unicode (fancy) or ASCII table borders and markers.
    # @param value [String, Symbol] The value to normalize
    # @return [Symbol] The normalized symbol (:default, :fancy, or :ascii)
    # @raise [OptionParser::InvalidArgument] If value is invalid
    module_function def normalize_output_chars(value)
      normalized = OUTPUT_CHARS_MAP[value.to_s.downcase]
      return normalized if normalized

      raise OptionParser::InvalidArgument, value.to_s
    end
  end
end
