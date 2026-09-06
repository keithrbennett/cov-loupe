# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/repositories/coverage_repository'
require 'fileutils'
require 'tmpdir'

RSpec.describe CovLoupe::Repositories::CoverageRepository do
  subject(:repo) { described_class.new(root: root, coverage_file_path: resultset_arg, logger: logger) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:resultset_arg) { nil }
  let(:logger) { instance_double('CovLoupe::Logger', safe_log: nil) }

  # Helper to set up volume case sensitivity mocking and resultset with custom coverage data
  def setup_volume_and_coverage(case_sensitive:, coverage_data:)
    # Mock volume_case_sensitive? to return the specified value for any arguments
    # (can be called with a path or with no args, defaulting to Dir.pwd)
    allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?)
      .and_return(case_sensitive)

    # Set up the resultset with the provided coverage data
    mock_resultset_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP, coverage: coverage_data)
  end

  # End-to-end check of the coverage.json path: a real file on disk, found
  # by the resolver's default candidates and loaded through the repository.
  describe 'with a real coverage/coverage.json on disk' do
    subject(:repo) { described_class.new(root: tmp_root, logger: logger) }

    let(:tmp_root) { Dir.mktmpdir }
    let(:foo_path) { File.join(tmp_root, 'lib', 'foo.rb') }
    let(:timestamp) { '2026-07-01T12:00:00.000+00:00' }

    before do
      FileUtils.mkdir_p(File.dirname(foo_path))
      FileUtils.mkdir_p(File.join(tmp_root, 'coverage'))
      File.write(foo_path, "# frozen_string_literal: true\n")
      File.write(File.join(tmp_root, 'coverage', 'coverage.json'), JSON.generate(
        'meta'     => {
          'schema_version'    => '1.0',
          'simplecov_version' => '1.0.0',
          'command_name'      => 'RSpec',
          'timestamp'         => timestamp,
        },
        # SimpleCov 1.0 writes project-relative keys.
        'coverage' => { 'lib/foo.rb' => { 'lines' => [1, 0, nil, 'ignored'] } },
        'groups'   => {}
      ))
    end

    after { FileUtils.remove_entry(tmp_root) }

    it 'discovers coverage/coverage.json without an explicit path' do
      expect(repo.coverage_file_path).to eq(File.join(tmp_root, 'coverage', 'coverage.json'))
    end

    it 'normalizes the project-relative key to an absolute project path' do
      expect(repo.coverage_map.keys).to eq([foo_path])
    end

    it 'exposes the coverage lines with "ignored" markers mapped to nil' do
      expect(repo.coverage_map.fetch(foo_path)['lines']).to eq([1, 0, nil, nil])
    end

    it 'reads the ISO 8601 meta timestamp as epoch seconds' do
      expect(repo.timestamp).to eq(Time.parse(timestamp).to_i)
    end
  end

  describe '#initialize' do
    context 'with valid data' do
      it 'loads coverage map' do
        expect(repo.coverage_map).not_to be_empty
        expect(repo.coverage_map).to have_key(File.join(root, 'lib', 'foo.rb'))
      end

      it 'normalizes keys to absolute paths' do
        repo.coverage_map.each_key do |key|
          expect(Pathname.new(key)).to be_absolute
        end
      end

      it 'sets timestamp' do
        expect(repo.timestamp).to be > 0
      end

      it 'resolves resultset path' do
        expected = File.join(root, 'coverage', '.resultset.json')
        expect(repo.coverage_file_path).to eq(expected)
      end
    end

    context 'when volume sensitivity detection fails' do
      before do
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).and_call_original
        allow(CovLoupe::PathUtils).to receive(:volume_case_sensitive?).with(root).and_raise(IOError)
      end

      it 'falls back to case-insensitive (false)' do
        expect(repo.instance_variable_get(:@volume_case_sensitive)).to be false
      end
    end

    context 'when loading fails' do
      let(:resultset_arg) { '/nonexistent/path' }

      it 'raises error' do
        expect do
          repo
        end.to raise_error(CovLoupe::CoverageFileNotFoundError)
      end
    end

    context 'when underlying loader raises generic error' do
      before do
        allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file).and_return('dummy')
        allow(CovLoupe::CoverageFileLoader).to receive(:load).and_raise(RuntimeError.new('Boom'))
      end

      it 'wraps RuntimeError as UnknownError' do
        expect do
          repo
        end.to raise_error(CovLoupe::UnknownError, /Boom/)
      end
    end

    # Tests for collision detection during path normalization.
    # When multiple keys in the resultset normalize to the same absolute path,
    # this indicates problematic data that would cause silent overwrites.
    # The repository should detect and report these collisions with clear errors.
    context 'when resultset contains duplicate normalized paths' do
      # Tests the most common collision scenario: same file referenced by
      # both relative path and absolute path in the coverage data.
      # Example: "lib/foo.rb" and "/full/path/lib/foo.rb" both normalize
      # to the same absolute path, causing one entry to silently overwrite the other
      # without collision detection.
      context 'with relative and absolute path collision' do
        let(:abs_foo_path) { File.join(root, 'lib', 'foo.rb') }
        let(:rel_foo_path) { 'lib/foo.rb' }

        before do
          # Simulate a resultset with both relative and absolute paths for the same file
          # Note: the 'lines' arrays differ to show that data would be lost
          coverage_data = {
            rel_foo_path => { 'lines' => [1, 0, nil, 2] },
            abs_foo_path => { 'lines' => [1, 1, nil, 2] },
          }
          mock_resultset_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP, coverage: coverage_data)
        end

        it 'raises CoverageDataError with details about colliding keys including originals' do
          expect { repo }.to raise_error(CovLoupe::CoverageDataError) do |error|
            expect(error.message).to include('Duplicate paths detected after normalization')
            expect(error.message).to match(/#{Regexp.escape(rel_foo_path)}/)
          end
        end
      end

      # Tests that multiple simultaneous collisions are all detected and reported.
      # This verifies the error message includes details for every collision found,
      # not just the first one encountered.
      context 'with multiple collisions' do
        let(:abs_foo_path) { File.join(root, 'lib', 'foo.rb') }
        let(:abs_bar_path) { File.join(root, 'lib', 'bar.rb') }

        before do
          # Simulate a resultset with collisions for multiple files
          coverage_data = {
            'lib/foo.rb' => { 'lines' => [1, 0] },
            abs_foo_path => { 'lines' => [1, 1] },
            'lib/bar.rb' => { 'lines' => [2, 0] },
            abs_bar_path => { 'lines' => [2, 2] },
          }
          mock_resultset_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP, coverage: coverage_data)
        end

        it 'raises CoverageDataError listing all collisions in JSON format' do
          expect do
            repo
          end.to raise_error(CovLoupe::CoverageDataError) do |error|
            # Verify both files appear in the error message
            expect(error.message).to include('lib/foo.rb')
            expect(error.message).to include('lib/bar.rb')

            # Verify the error message contains valid JSON
            # Example: "/full/path/lib/foo.rb": ["lib/foo.rb", "/full/path/lib/foo.rb"]
            json_match = error.message.match(/\{.*\}/m)
            expect(json_match).not_to be_nil

            parsed = JSON.parse(json_match[0])
            expect(parsed).to have_key(abs_foo_path)
            expect(parsed).to have_key(abs_bar_path)
            expect(parsed[abs_foo_path]).to include('lib/foo.rb', abs_foo_path)
            expect(parsed[abs_bar_path]).to include('lib/bar.rb', abs_bar_path)
          end
        end
      end

      # Tests that case-only variations are detected as collisions on case-insensitive volumes.
      # On macOS/Windows, "Foo.rb" and "foo.rb" refer to the same file and should be
      # detected as a collision to prevent duplicate entries in coverage reports.
      context 'with case-only path collision on case-insensitive volume' do
        let(:foo_path_lower) { File.join(root, 'lib', 'foo.rb') }
        let(:foo_path_upper) { File.join(root, 'lib', 'Foo.rb') }
        let(:coverage_data) do
          {
            foo_path_lower => { 'lines' => [1, 0, nil, 2] },
            foo_path_upper => { 'lines' => [1, 1, nil, 2] },
          }
        end

        before do
          setup_volume_and_coverage(case_sensitive: false, coverage_data: coverage_data)
        end

        it 'raises CoverageDataError detecting case collision with original variants' do
          expect { repo }.to raise_error(CovLoupe::CoverageDataError) do |error|
            expect(error.message).to include('Duplicate paths detected after normalization')
            expect(error.message).to include('foo.rb')
            expect(error.message).to include('Foo.rb')
          end
        end
      end

      # Tests that case-only collisions are NOT detected on case-sensitive volumes.
      # On Linux and other case-sensitive systems, "Foo.rb" and "foo.rb" are distinct files
      # and should not be treated as collisions.
      context 'with case-only path differences on case-sensitive volume' do
        let(:foo_path_lower) { File.join(root, 'lib', 'foo.rb') }
        let(:foo_path_upper) { File.join(root, 'lib', 'Foo.rb') }
        let(:coverage_data) do
          {
            foo_path_lower => { 'lines' => [1, 0, nil, 2] },
            foo_path_upper => { 'lines' => [1, 1, nil, 2] },
          }
        end

        before do
          setup_volume_and_coverage(case_sensitive: true, coverage_data: coverage_data)
        end

        it 'does not raise an error for case-only differences' do
          expect { repo }.not_to raise_error
        end

        it 'preserves both entries in the coverage map' do
          expect(repo.coverage_map).to have_key(foo_path_lower)
          expect(repo.coverage_map).to have_key(foo_path_upper)
          expect(repo.coverage_map.size).to be >= 2
        end

        it 'preserves the original case in coverage map keys' do
          expect(repo.coverage_map.keys).to include(foo_path_lower, foo_path_upper)
        end
      end

      # Tests that original case is preserved in coverage map keys even when
      # collision detection uses case normalization.
      context 'with mixed-case paths on case-insensitive volume without collisions' do
        let(:foo_path_upper) { File.join(root, 'lib', 'Foo.rb') }
        let(:coverage_data) do
          { foo_path_upper => { 'lines' => [1, 1, nil, 2] } }
        end

        before do
          setup_volume_and_coverage(case_sensitive: false, coverage_data: coverage_data)
        end

        it 'preserves the original case in the coverage map key' do
          expect(repo.coverage_map).to have_key(foo_path_upper)
          # Verify it's not downcased
          expect(repo.coverage_map.keys.grep(/Foo\.rb/)).not_to be_empty
        end
      end
    end
  end
end
