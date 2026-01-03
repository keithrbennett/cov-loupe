# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageModel, 'list performance' do
  subject(:model) { described_class.new(root: root) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  describe '#list' do
    it 'does not call the resolver for well-formed entries' do
      # The resolver should only be called if entries are malformed.
      # For normal, well-formed coverage data, we should extract lines
      # directly from the entry without invoking the resolver.
      expect(CovLoupe::Resolvers::CoverageLineResolver).not_to receive(:new)

      result = model.list
      expect(result['files']).not_to be_empty
    end

    it 'extracts lines directly from coverage entries' do
      # Verify that list returns correct data without needing resolver
      result = model.list

      files = result['files']
      expect(files).not_to be_empty

      # Verify each file has expected structure
      files.each do |file_data|
        expect(file_data).to include('file', 'covered', 'total', 'percent_covered')
        expect(file_data['total']).to be > 0
      end
    end
  end
end
