# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Resolvers::CoverageLineResolver do
  describe '#lookup_lines extended' do
    let(:root) { '/project' }

    context 'when basename matches but path does not' do
      it 'raises a coverage entry error when only basename matches (no basename fallback)' do
        abs_path = '/project/lib/foo.rb'
        # Data is stored under a different path but same filename
        cov_data = {
          '/other/path/foo.rb' => { 'lines' => [1, 0, 1] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)

        # Basename matching has been removed to prevent silent data corruption
        expect do
          resolver.lookup_lines(abs_path)
        end.to raise_error(CovLoupe::CoverageEntryNotFoundError, /No coverage entry found/)
      end

      it 'returns exact match when both basename and path match' do
        abs_path = '/project/lib/foo.rb'
        cov_data = {
          '/project/lib/foo.rb' => { 'lines' => [1, 1, 1] },
          '/other/path/foo.rb'  => { 'lines' => [0, 0, 0] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)
        lines = resolver.lookup_lines(abs_path)

        expect(lines).to eq([1, 1, 1])
      end

      it 'raises a coverage entry error when path does not match despite basename collision' do
        abs_path = '/project/lib/common.rb'
        cov_data = {
          '/path/a/common.rb' => { 'lines' => [1] },
          '/path/b/common.rb' => { 'lines' => [2] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)
        expect do
          resolver.lookup_lines(abs_path)
        end.to raise_error(CovLoupe::CoverageEntryNotFoundError, /No coverage entry found/)
      end
    end

    context 'with configured root' do
      it 'uses configured root for relative path resolution' do
        root = '/custom/root'
        relative_path = 'lib/bar.rb'
        abs_path = File.join(root, relative_path)

        cov_data = {
          relative_path => { 'lines' => [1, 0] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)

        # Stub Dir.pwd to ensure the resolver doesn't use it for fallback resolution.
        allow(Dir).to receive(:pwd).and_return('/wrong/place')

        lines = resolver.lookup_lines(abs_path)
        expect(lines).to eq([1, 0])
      end
    end
  end
end
