# frozen_string_literal: true

module CovLoupe
  # Central module for choosing how cov-loupe draws its own decoration: Unicode (fancy) or ASCII.
  #
  # This module provides:
  # - Mode resolution (:default -> :fancy or :ascii based on output encoding)
  # - Character sets for table borders (Unicode box-drawing vs ASCII)
  #
  # The mode never alters data (file paths, source lines, messages); only cov-loupe's own table
  # borders and coverage markers change. In ASCII mode, JSON output also escapes non-ASCII
  # characters as \uXXXX, which encodes the data without changing it.
  #
  # Usage:
  #   mode = OutputChars.resolve_mode(:default)  # => :fancy or :ascii
  #   charset = OutputChars.charset_for(mode)    # => hash of border chars
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

      # Checks if ASCII decoration is in effect for the given mode.
      #
      # @param mode [Symbol] :fancy, :ascii, or :default
      # @param io [IO] The output stream for resolving :default (default: $stdout)
      # @return [Boolean] true if ASCII mode is in effect
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
    end
  end
end
