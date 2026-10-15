# frozen_string_literal: true

module CovLoupe
  # A pluggable boolean type converter for OptionParser.
  # Accepts various string representations of true/false and converts them to boolean values.
  #
  # Usage with OptionParser:
  #   parser.accept(BooleanType) { |v| BooleanType.parse(v) }
  #   parser.on('--flag [BOOLEAN]', BooleanType) { |v| config.flag = v }
  #
  # Supported values (case-insensitive):
  #   true:  yes, y, true, t, on, +, 1
  #   false: no, n, false, f, off, -, 0
  #   nil:   treated as true (for bare flags like --flag)
  #
  # Examples:
  #   --flag         → true
  #   --flag=yes     → true
  #   --flag=no      → false
  #   --flag yes     → true
  #   --flag false   → false
  #
  # @api private
  class BooleanType
    # Values that map to true
    TRUE_VALUES = %w[yes y true t on + 1].freeze

    # Values that map to false
    FALSE_VALUES = %w[no n false f off - 0].freeze

    # All valid boolean string values: %w{yes no y n true false t f on off + - 1 0 }
    VALID_VALUES = TRUE_VALUES.zip(FALSE_VALUES).flatten.freeze

    # String representation for help messages ('yes/no/true/false/t/f/on/off/y/n/+/-/1/0')
    BOOLEAN_VALUES_DISPLAY_STRING = VALID_VALUES.join('/').freeze

    # Pattern object for OptionParser.
    # Proc objects get treated as blocks, and Module instances are rejected outright,
    # so we expose a singleton that only responds to #match like a regex.
    IS_BOOLEAN_STRING_VALUE = Object.new
    IS_BOOLEAN_STRING_VALUE.define_singleton_method(:match) do |value|
      BooleanType.valid?(value) ? value : nil
    end

    class << self
      # Parse a string value into a boolean.
      #
      # @param value [String, nil] The value to parse
      # @return [Boolean] true or false
      # @raise [ArgumentError] if the value is not a valid boolean string
      def parse(value)
        # nil means bare flag (e.g., --flag without a value) → true
        return true if value.nil?

        normalized = value.to_s.strip.downcase

        return true if TRUE_VALUES.include?(normalized)
        return false if FALSE_VALUES.include?(normalized)

        raise ArgumentError, "invalid boolean value: #{value.inspect}. " \
                            "Valid values: #{VALID_VALUES.join(', ')}"
      end

      # Check if a value is a valid boolean string.
      #
      # @param value [String, nil] The value to check
      # @return [Boolean] true if valid, false otherwise
      def valid?(value)
        return true if value.nil?

        VALID_VALUES.include?(value.to_s.strip.downcase)
      end

      # Pattern matching for OptionParser (called via ===)
      # This is called to determine if a token should be consumed as the option's argument.
      # Returning nil signals OptionParser to NOT consume the token.
      #
      # @param value [String, nil] The value to match
      # @return [Boolean, nil] The parsed boolean if valid, or nil to reject the token
      def ===(value)
        # nil means optional argument not provided - accept as match
        return true if value.nil?

        # Only consume the token if it's a valid boolean value
        # This prevents consuming subcommand names or other arguments
        return true if valid?(value)

        # Invalid value - don't consume it, let OptionParser treat it as the next argument
        nil
      end
    end
  end
end
