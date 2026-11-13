# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Resources do
  describe '.cli_url_for' do
    {
      'repo' => 'https://github.com/keithrbennett/cov-loupe',
      'docs' => 'https://keithrbennett.github.io/cov-loupe/',
    }.each do |name, expected_url|
      it "returns correct value for '#{name}'" do
        expect(described_class.cli_url_for(name)).to eq(expected_url)
      end
    end

    it "returns local README path for 'docs-local'" do
      expect(described_class.cli_url_for('docs-local')).to end_with('README.md')
    end

    it 'raises error for unknown resource' do
      expect do
        described_class.cli_url_for('unknown')
      end.to raise_error(CovLoupe::UsageError, /Unknown resource/)
    end
  end

  describe '.payload_map' do
    it 'uses snake_case keys with the RESOURCE_MAP values' do
      expect(described_class.payload_map).to eq(
        'repo'       => described_class::RESOURCE_MAP['repo'],
        'docs'       => described_class::RESOURCE_MAP['docs'],
        'docs_local' => described_class::RESOURCE_MAP['docs-local']
      )
    end
  end

  describe 'RESOURCE_MAP' do
    subject(:result) { described_class::RESOURCE_MAP }

    it 'has exactly the canonical keys' do
      expect(result.keys).to match_array(%w[repo docs docs-local])
    end

    it 'maps repo to the GitHub URL' do
      expect(result['repo']).to eq('https://github.com/keithrbennett/cov-loupe')
    end

    it 'maps docs to the documentation web URL' do
      expect(result['docs']).to eq('https://keithrbennett.github.io/cov-loupe/')
    end

    it 'maps docs-local to an existing README file' do
      expect(result['docs-local']).to end_with('README.md')
      expect(File.exist?(result['docs-local'])).to be true
    end
  end
end
