# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Resolvers::CoverageLineResolver do
  describe '#lookup_lines' do
    let(:root) { '/project' }

    context 'with direct path matching' do
      it 'returns lines array for exact path match' do
        abs_path = '/project/lib/foo.rb'
        cov_data = {
          abs_path => { 'lines' => [1, 0, nil, 2] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)
        lines = resolver.lookup_lines(abs_path)

        expect(lines).to eq([1, 0, nil, 2])
      end

      it 'returns lines array when entry has lines directly' do
        path = '/tmp/test.rb'
        cov_data = {
          path => { 'lines' => [1, 1, 1] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)
        expect(resolver.lookup_lines(path)).to eq([1, 1, 1])
      end
    end

    context 'with root stripping fallback' do
      ['/project', '/'].each do |root|
        it "finds relative path when absolute path includes root #{root}" do
          relative_path = 'lib/bar.rb'
          abs_path = File.join(root, relative_path)
          cov_data = {
            relative_path => { 'lines' => [1, 0, 1] },
          }

          resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)
          lines = resolver.lookup_lines(abs_path)

          expect(lines).to eq([1, 0, 1])
        end
      end

      it 'raises FileError when absolute path does not start with root and no exact match' do
        cov_data = {
          'lib/baz.rb' => { 'lines' => [1, 1] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)

        # Basename fallback has been removed to prevent silent data corruption.
        # This now raises FileError as expected.
        expect do
          resolver.lookup_lines('/other/directory/lib/baz.rb')
        end.to raise_error(CovLoupe::FileError, /No coverage entry found/)
      end
    end

    context 'when handling errors' do
      let(:cov_data) do
        {
          '/project/lib/foo.rb'         => { 'other_key' => 'value' },
          '/project/lib/branch_only.rb' => {
            'branches' => { '[:if, 0, 1, 0, 1, 4]' => { '[:then, 1, 1, 0, 1, 4]' => 1 } },
          },
        }
      end

      [
        {
          desc:  'raises FileError when file is not found in coverage data',
          path:  '/project/lib/missing.rb',
          error: CovLoupe::FileError,
          msg:   /No coverage entry found/,
        },
        {
          desc:      'raises FileError when coverage data is empty',
          path:      '/any/path.rb',
          empty_cov: true,
          error:     CovLoupe::FileError,
          msg:       /No coverage entry found/,
        },
        {
          desc:  'raises CorruptCoverageDataError when entry exists but has no valid lines',
          path:  '/project/lib/foo.rb',
          error: CovLoupe::CorruptCoverageDataError,
          msg:   /Entry for .* has no valid lines/,
        },
        {
          desc:  'raises CorruptCoverageDataError for branch-only coverage (no lines array)',
          path:  '/project/lib/branch_only.rb',
          error: CovLoupe::CorruptCoverageDataError,
          msg:   /Entry for .* has no valid lines/,
        },
      ].each do |tc|
        it tc[:desc] do
          data = tc[:empty_cov] ? {} : cov_data
          resolver = described_class.new(data, root: root, volume_case_sensitive: true)

          expect do
            resolver.lookup_lines(tc[:path])
          end.to raise_error(tc[:error], tc[:msg])
        end
      end
    end

    context 'when validating line array elements' do
      [
        {
          desc:    'raises CoverageDataError when lines array contains strings',
          lines:   [1, 0, 'invalid', 2],
          invalid: ['invalid'],
        },
        {
          desc:    'raises CoverageDataError when lines array contains floats',
          lines:   [1, 0, 3.14, 2],
          invalid: [3.14],
        },
        {
          desc:    'raises CoverageDataError when lines array contains mixed invalid types',
          lines:   [1, 0, 'string', 3.14, true, nil, 2],
          invalid: ['string', 3.14, true],
        },
        {
          desc:    'raises CoverageDataError when lines array contains hashes',
          lines:   [1, 0, { 'key' => 'value' }, 2],
          invalid: [{ 'key' => 'value' }],
        },
        {
          desc:    'raises CoverageDataError when lines array contains arrays',
          lines:   [1, 0, [1, 2], 2],
          invalid: [[1, 2]],
        },
      ].each do |tc|
        it tc[:desc] do
          cov_data = {
            '/project/lib/malformed.rb' => { 'lines' => tc[:lines] },
          }
          resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)

          expect do
            resolver.lookup_lines('/project/lib/malformed.rb')
          end.to raise_error(CovLoupe::CoverageDataError) do |error|
            expect(error.message).to include('Invalid coverage line array', 'non-integer elements')
            tc[:invalid].each do |invalid_elem|
              expect(error.message).to include(invalid_elem.inspect)
            end
          end
        end
      end

      it 'accepts valid lines arrays with only integers and nil' do
        cov_data = {
          '/project/lib/valid.rb' => { 'lines' => [1, 0, nil, 2, nil, 0] },
        }
        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: true)

        lines = resolver.lookup_lines('/project/lib/valid.rb')
        expect(lines).to eq([1, 0, nil, 2, nil, 0])
      end
    end

    context 'with volume-specific path normalization' do
      [
        { sensitive: true, desc: 'case-sensitive', raises: true },
        { sensitive: false, desc: 'case-insensitive', raises: false },
      ].each do |tc|
        it "applies #{tc[:desc]} matching when volume_case_sensitive is #{tc[:sensitive]}" do
          cov_data = { '/project/lib/Foo.rb' => { 'lines' => [1, 0] } }
          resolver = described_class.new(cov_data, root: root,
            volume_case_sensitive: tc[:sensitive])

          if tc[:raises]
            expect { resolver.lookup_lines('/project/lib/foo.rb') }
              .to raise_error(CovLoupe::FileError, /No coverage entry found/)
          else
            expect(resolver.lookup_lines('/project/lib/foo.rb')).to eq([1, 0])
          end
        end
      end
    end

    context 'with normalized path resolution edge cases' do
      it 'resolves single normalized match when exact match fails on case-insensitive FS' do
        # Simulate case-insensitive volume behavior
        allow(CovLoupe).to receive(:windows?).and_return(false)

        cov_data = {
          'lib/Foo.rb' => { 'lines' => [1, 2, 3] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: false)

        # Request with different casing - should normalize and find the match
        lines = resolver.lookup_lines('lib/foo.rb')
        expect(lines).to eq([1, 2, 3])
      end

      it 'raises FileError for ambiguous normalized matches on case-insensitive filesystems' do
        # Simulate case-insensitive volume where 'Foo.rb' and 'foo.rb' both normalize to 'foo.rb'
        allow(CovLoupe).to receive(:windows?).and_return(false)

        cov_data = {
          'lib/Foo.rb' => { 'lines' => [1, 2, 3] },
          'lib/foo.rb' => { 'lines' => [4, 5, 6] },
        }

        resolver = described_class.new(cov_data, root: root, volume_case_sensitive: false)

        # Both keys normalize to the same path, causing ambiguity
        expect do
          resolver.lookup_lines('lib/FOO.rb')
        end.to raise_error(CovLoupe::FileError, /Multiple coverage entries match path/)
      end
    end

    context 'with path normalization' do
      [
        {
          desc: 'normalizes backslashes on Windows',
          windows: true, sensitive: true,
          data: { 'lib/utils/Helper.rb' => { 'lines' => [10, 20, 30] } },
          lookup: 'lib\\utils\\Helper.rb',
          expected: [10, 20, 30]
        },
        {
          desc: 'normalizes both slashes and case on Windows with case-insensitive filesystem',
          windows: true, sensitive: false,
          data: { 'lib/utils/Helper.rb' => { 'lines' => [10, 20, 30] } },
          lookup: 'lib\\utils\\HELPER.rb',
          expected: [10, 20, 30]
        },
        {
          desc: 'does not normalize on case-sensitive volumes',
          windows: false, sensitive: true,
          data: { 'lib/Helper.rb' => { 'lines' => [1, 2] } },
          lookup: 'lib\\helper.rb',
          error: CovLoupe::FileError
        },
        {
          desc: 'normalizes case on case-insensitive volumes',
          windows: false, sensitive: false,
          data: { 'lib/Helper.rb' => { 'lines' => [1, 2, 3] } },
          lookup: 'lib/HELPER.rb',
          expected: [1, 2, 3]
        },
      ].each do |tc|
        it tc[:desc] do
          allow(CovLoupe).to receive(:windows?).and_return(tc[:windows])

          resolver = described_class.new(tc[:data], root: root,
            volume_case_sensitive: tc[:sensitive])

          if tc[:error]
            expect { resolver.lookup_lines(tc[:lookup]) }
              .to raise_error(tc[:error], /No coverage entry found/)
          else
            expect(resolver.lookup_lines(tc[:lookup])).to eq(tc[:expected])
          end
        end
      end
    end
  end
end
