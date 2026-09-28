# frozen_string_literal: true

require_relative 'version'

module CovLoupe
  # Adds the version of a coverage payload without changing the input hash.
  module PayloadSchema
    SCHEMA_DIR = File.expand_path('schemas', __dir__).freeze
    SCHEMA_NAMES = %w[summary raw uncovered detailed list totals validate_result help].freeze

    # Returns the absolute path to a shipped JSON Schema for a payload shape.
    #
    # @param name [String, Symbol] One of SCHEMA_NAMES
    # @param version [Integer] Payload schema version (defaults to the current version)
    # @return [String] Absolute path to the JSON Schema file
    # @raise [ArgumentError] If the name or version is not shipped
    def self.schema_path(name, version: SCHEMA_VERSION)
      schema_name = name.to_s
      raise ArgumentError, "Unknown payload schema: #{name.inspect}" unless SCHEMA_NAMES.include?(schema_name)

      unless version.is_a?(Integer) && version.positive?
        raise ArgumentError, "Unknown payload schema version: #{version.inspect}"
      end

      path = File.join(SCHEMA_DIR, "v#{version}", "#{schema_name}.json")
      raise ArgumentError, "Unknown payload schema version: #{version.inspect}" unless File.file?(path)

      path
    end

    def self.add(payload)
      raise TypeError, 'Structured payload must be a Hash' unless payload.is_a?(Hash)

      payload.each_with_object('schema_version' => SCHEMA_VERSION) do |(key, value), versioned|
        versioned[key] = value unless key.to_s == 'schema_version'
      end
    end
  end
end
