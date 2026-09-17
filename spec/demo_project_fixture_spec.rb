# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'docs/fixtures/demo_project fixture' do
  let(:fixture_root) { File.expand_path('../docs/fixtures/demo_project', __dir__) }
  let(:coverage_document) do
    JSON.parse(File.read(File.join(fixture_root, 'coverage', 'coverage.json')))
  end

  it 'pins the sentinel coverage timestamp so fresh clones reproduce the documented outputs' do
    expect(coverage_document.dig('meta', 'timestamp')).to eq('2099-01-01T00:00:00.000Z')
  end

  it 'keeps every recorded line array in sync with its source file' do
    mismatches = coverage_document['coverage'].filter_map do |relative_path, entry|
      source_path = File.join(fixture_root, relative_path)
      next "#{relative_path}: missing on disk" unless File.exist?(source_path)

      source_lines = File.readlines(source_path).size
      next if source_lines == entry['lines'].size

      "#{relative_path}: #{source_lines} source lines vs #{entry['lines'].size} coverage lines"
    end

    expect(mismatches).to be_empty
  end
end
