# frozen_string_literal: true

require 'json_schemer'

module PayloadSchemaTestHelpers
  def strict_payload_schema(name)
    schema = JSON.parse(File.read(CovLoupe::PayloadSchema.schema_path(name)))
    close_schema_objects(schema)
  end

  def expect_schema_valid(name, payload)
    errors = JSONSchemer.schema(strict_payload_schema(name)).validate(payload).to_a
    expect(errors).to be_empty, "#{name} schema errors: #{errors.map { |error| error['error'] }.join('; ')}"
  end

  private def close_schema_objects(node)
    case node
    when Hash
      node.each_value { |value| close_schema_objects(value) }
      node['additionalProperties'] = false if node['type'] == 'object'
    when Array
      node.each { |value| close_schema_objects(value) }
    end
    node
  end
end
