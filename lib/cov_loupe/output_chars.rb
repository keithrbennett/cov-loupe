# frozen_string_literal: true

module CovLoupe
  # Central module for controlling ASCII vs Unicode (fancy) output.
  #
  # This module provides:
  # - Mode resolution (:default -> :fancy or :ascii based on output encoding)
  # - Character sets for table borders (Unicode box-drawing vs ASCII)
  # - Text conversion for ensuring ASCII-only output when needed
  #
  # Usage:
  #   mode = OutputChars.resolve_mode(:default)  # => :fancy or :ascii
  #   charset = OutputChars.charset_for(mode)    # => hash of border chars
  #   text = OutputChars.convert("café", mode)   # => "caf?" in :ascii mode
  #
  # @api private
  module OutputChars
    # Valid output character modes
    MODES = %i[default fancy ascii].freeze

    # Unicode box-drawing characters (fancy mode)
    UNICODE_CHARSET = {
      top_left:     "\u250C",
      top_right:    "\u2510",
      bottom_left:  "\u2514",
      bottom_right: "\u2518",
      horizontal:   "\u2500",
      vertical:     "\u2502",
      top_tee:      "\u252C",
      bottom_tee:   "\u2534",
      left_tee:     "\u251C",
      right_tee:    "\u2524",
      cross:        "\u253C",
    }.freeze

    # ASCII characters for table borders (ascii mode)
    ASCII_CHARSET = {
      top_left:     '+',
      top_right:    '+',
      bottom_left:  '+',
      bottom_right: '+',
      horizontal:   '-',
      vertical:     '|',
      top_tee:      '+',
      bottom_tee:   '+',
      left_tee:     '+',
      right_tee:    '+',
      cross:        '+',
    }.freeze

    class << self
      # Resolves :default mode to :fancy or :ascii based on output encoding.
      #
      # @param mode [Symbol] One of :default, :fancy, or :ascii
      # @param io [IO] The output stream to check encoding for (default: $stdout)
      # @return [Symbol] :fancy or :ascii
      def resolve_mode(mode, io: $stdout)
        case mode
        when :fancy then :fancy
        when :ascii then :ascii
        when :default then default_mode_for(io)
        else
          raise ArgumentError, "Invalid output_chars mode: #{mode.inspect}"
        end
      end

      # Returns the character set hash for the given mode.
      #
      # @param mode [Symbol] :fancy or :ascii (use resolve_mode first if :default)
      # @return [Hash] Character set with keys like :top_left, :horizontal, etc.
      def charset_for(mode)
        case mode
        when :fancy then UNICODE_CHARSET
        when :ascii then ASCII_CHARSET
        when :default then charset_for(resolve_mode(:default))
        else
          raise ArgumentError, "Invalid output_chars mode: #{mode.inspect}"
        end
      end

      # Converts text to ASCII-only when in :ascii mode.
      # In :fancy mode, returns text unchanged.
      #
      # @param text [String] The text to convert
      # @param mode [Symbol] :fancy, :ascii, or :default
      # @param io [IO] The output stream for resolving :default (default: $stdout)
      # @return [String] Original text (:fancy) or ASCII-only text (:ascii)
      def convert(text, mode, io: $stdout)
        return text if text.nil?

        resolved = mode == :default ? resolve_mode(mode, io: io) : mode
        return text if resolved == :fancy

        to_ascii(text)
      end

      # Checks if output should be ASCII-only for the given mode.
      #
      # @param mode [Symbol] :fancy, :ascii, or :default
      # @param io [IO] The output stream for resolving :default (default: $stdout)
      # @return [Boolean] true if ASCII-only output is required
      def ascii_mode?(mode, io: $stdout)
        resolved = mode == :default ? resolve_mode(mode, io: io) : mode
        resolved == :ascii
      end

      private def default_mode_for(io)
        encoding = io.respond_to?(:external_encoding) ? io.external_encoding : nil
        encoding ||= Encoding.default_external

        utf8_compatible?(encoding) ? :fancy : :ascii
      end

      # Checks if the encoding is UTF-8 compatible.
      #
      # @param encoding [Encoding, nil] The encoding to check
      # @return [Boolean] true if UTF-8 compatible
      private def utf8_compatible?(encoding)
        return false if encoding.nil?

        encoding_name = encoding.name.upcase
        encoding_name.include?('UTF-8') || encoding_name == 'UTF8'
      end

      # Converts a string to ASCII-only, replacing non-ASCII characters.
      #
      # Uses transliteration for common characters where sensible,
      # falls back to '?' for others. This is a best-effort conversion
      # that prioritizes readability over exactness.
      #
      # @param text [String] The text to convert
      # @return [String] ASCII-only text
      private def to_ascii(text)
        text.each_char.map do |char|
          if char.ord < 128
            char
          else
            transliterate(char)
          end
        end.join
      end

      # Transliterates a single non-ASCII character to ASCII.
      #
      # @param char [String] Single character to transliterate
      # @return [String] ASCII replacement (may be multiple characters)
      private def transliterate(char)
        # Common transliterations for readability
        TRANSLITERATIONS[char] || '?'
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength
    end

    # Common character transliterations to ASCII.
    # This covers common accented characters and symbols users might encounter.
    # Box-drawing characters are not included here; they're handled by charset_for.
    TRANSLITERATIONS = {
      # Accented vowels
      'á' => 'a', 'à' => 'a', 'â' => 'a', 'ä' => 'a', 'ã' => 'a', 'å' => 'a',
      'Á' => 'A', 'À' => 'A', 'Â' => 'A', 'Ä' => 'A', 'Ã' => 'A', 'Å' => 'A',
      'é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e',
      'É' => 'E', 'È' => 'E', 'Ê' => 'E', 'Ë' => 'E',
      'í' => 'i', 'ì' => 'i', 'î' => 'i', 'ï' => 'i',
      'Í' => 'I', 'Ì' => 'I', 'Î' => 'I', 'Ï' => 'I',
      'ó' => 'o', 'ò' => 'o', 'ô' => 'o', 'ö' => 'o', 'õ' => 'o', 'ø' => 'o',
      'Ó' => 'O', 'Ò' => 'O', 'Ô' => 'O', 'Ö' => 'O', 'Õ' => 'O', 'Ø' => 'O',
      'ú' => 'u', 'ù' => 'u', 'û' => 'u', 'ü' => 'u',
      'Ú' => 'U', 'Ù' => 'U', 'Û' => 'U', 'Ü' => 'U',
      # Other common characters
      'ñ' => 'n', 'Ñ' => 'N',
      'ç' => 'c', 'Ç' => 'C',
      'ß' => 'ss',
      'æ' => 'ae', 'Æ' => 'AE',
      'œ' => 'oe', 'Œ' => 'OE',
      # Common symbols
      "\u20AC" => 'EUR', "\u00A3" => 'GBP', "\u00A5" => 'JPY',
      "\u00A9" => '(c)', "\u00AE" => '(R)', "\u2122" => '(TM)',
      "\u00B0" => 'deg',
      "\u2026" => '...',
      "\u2018" => "'", "\u2019" => "'", "\u201C" => '"', "\u201D" => '"',
      "\u2013" => '-', "\u2014" => '--',
      "\u00D7" => 'x', "\u00F7" => '/',
      "\u2264" => '<=', "\u2265" => '>=', "\u2260" => '!=',
      "\u2192" => '->', "\u2190" => '<-', "\u2194" => '<->',
      "\u2713" => '[x]', "\u2717" => '[ ]', "\u2714" => '[x]', "\u2718" => '[ ]',
      # Bullets and list markers
      "\u2022" => '*', "\u25E6" => 'o', "\u25AA" => '-', "\u25B8" => '>',
      # Box-drawing (for any stray usage outside tables)
      "\u250C" => '+', "\u2510" => '+', "\u2514" => '+', "\u2518" => '+',
      "\u2500" => '-', "\u2502" => '|',
      "\u252C" => '+', "\u2534" => '+', "\u251C" => '+', "\u2524" => '+', "\u253C" => '+'
    }.freeze
  end
end
