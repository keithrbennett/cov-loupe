# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::PayloadSchema do
  include PayloadSchemaTestHelpers

  describe '.add' do
    it 'puts the version first without mutating the input' do
      payload = { 'file' => 'lib/foo.rb', 'summary' => { 'covered' => 2 } }
      result = described_class.add(payload)

      expect(result.keys).to eq(%w[schema_version file summary])
      expect(result['schema_version']).to eq(CovLoupe::SCHEMA_VERSION)
      expect(payload.keys).to eq(%w[file summary])
    end

    it 'is idempotent when the input already contains schema_version' do
      payload = { 'file' => 'lib/foo.rb', 'schema_version' => 999, 'summary' => {} }
      result = described_class.add(described_class.add(payload))

      expect(result.keys).to eq(%w[schema_version file summary])
      expect(result['schema_version']).to eq(CovLoupe::SCHEMA_VERSION)
      expect(payload['schema_version']).to eq(999)
    end

    it 'does not duplicate a symbol schema_version key when serialized' do
      result = described_class.add(schema_version: 999, file: 'lib/foo.rb')

      expect(result.keys).to eq(['schema_version', :file])
      expect(JSON.parse(JSON.generate(result)).keys).to eq(%w[schema_version file])
    end

    it 'rejects non-Hash input' do
      expect { described_class.add([]) }.to raise_error(TypeError, /must be a Hash/)
    end
  end

  describe '.schema_path' do
    it 'finds every supported name in the current version directory' do
      directory = File.join(described_class::SCHEMA_DIR, "v#{CovLoupe::SCHEMA_VERSION}")
      expected_files = described_class::SCHEMA_NAMES.map { |name| "#{name}.json" }.sort
      expect(Dir.children(directory).sort).to eq(expected_files)

      described_class::SCHEMA_NAMES.each do |name|
        expect(described_class.schema_path(name)).to eq(File.join(directory, "#{name}.json"))
      end
    end

    it 'accepts a symbol name and explicit version' do
      expect(described_class.schema_path(:summary, version: 1)).to end_with('/v1/summary.json')
    end

    it 'rejects unknown names and versions' do
      expect { described_class.schema_path('unknown') }
        .to raise_error(ArgumentError, /Unknown payload schema/)
      expect { described_class.schema_path('../summary') }
        .to raise_error(ArgumentError, /Unknown payload schema/)
      expect { described_class.schema_path('summary', version: 2) }
        .to raise_error(ArgumentError, /Unknown payload schema version/)
      expect { described_class.schema_path('summary', version: '1') }
        .to raise_error(ArgumentError, /Unknown payload schema version/)
    end
  end

  describe 'shipped v1 schemas' do
    described_class::SCHEMA_NAMES.each do |name|
      it "meta-validates #{name} against draft 2020-12" do
        schema = JSON.parse(File.read(described_class.schema_path(name)))

        expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
        expect(JSONSchemer.validate_schema(schema).to_a).to be_empty
        expect(JSON.generate(schema)).not_to include('"additionalProperties"')
      end
    end

    it 'rejects missing required keys and wrong value types in strict mode' do
      payload = described_class.add('file' => 'lib/foo.rb',
        'summary' => { 'covered' => 1, 'total' => 2, 'percentage' => 50.0 })
      schemer = JSONSchemer.schema(strict_payload_schema('summary'))

      expect(schemer).to be_valid(payload)
      expect(schemer).not_to be_valid(payload.except('summary'))
      expect(schemer).not_to be_valid(payload.merge('file' => 123))
      expect(schemer).not_to be_valid(payload.merge('unexpected' => true))
    end
  end
end
