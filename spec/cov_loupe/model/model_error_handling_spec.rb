# frozen_string_literal: true

require 'fileutils'
require 'spec_helper'

RSpec.describe CovLoupe::CoverageModel, 'error handling' do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  describe 'initialization error handling' do
    let(:valid_resultset) do
      {
        'RSpec'     => {
          'coverage' => {
            "lib/foo\x00bar.rb" => { 'lines' => [1, 0, 1] }, # Path with NULL byte
          },
        },
        'timestamp' => 1000,
      }
    end
    let(:malformed_resultset) do
      {
        'RSpec' => {
          'coverage' => 'not_a_hash', # Should be a hash, not a string
        },
      }
    end

    it 'raises CoverageDataError with message detail for invalid JSON format' do
      mock_json_parse_error(JSON::ParserError.new('unexpected token'))

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid coverage data format', 'unexpected token')
      end
    end

    it 'raises FilePermissionError when coverage file is not readable' do
      mock_file_read_error(Errno::EACCES.new('Permission denied'))

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::FilePermissionError) do |error|
        expect(error.message).to include('Permission denied reading coverage data')
      end
    end

    it 'raises CoverageDataError when resultset structure is invalid (TypeError)' do
      mock_resultset_data(malformed_resultset)

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid coverage data structure')
      end
    end

    it 'raises CoverageDataError when resultset structure causes NoMethodError' do
      # Create a resultset structure that will cause NoMethodError
      malformed_resultset = {
        'RSpec' => {
          'coverage' => {
            'file.rb' => nil, # Should have 'lines' key, this will cause NoMethodError
          },
        },
      }

      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(end_with('.resultset.json'), 'r')
        .and_return(StringIO.new(malformed_resultset.to_json))

      broken_map = instance_double('CoverageMap')
      allow(broken_map).to receive(:each)
        .and_raise(NoMethodError.new("undefined method `upcase' for nil:NilClass"))
      allow(CovLoupe::ResultsetLoader).to receive(:load).and_return(
        CovLoupe::ResultsetLoader::Result.new(coverage_map: broken_map,
          timestamp: 0, suite_names: ['RSpec'])
      )

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid coverage data structure')
      end
    end

    it 'raises CoverageDataError when path operations raise ArgumentError' do
      mock_resultset_data(valid_resultset, path_matcher: end_with('.resultset.json'))

      # Mock File.absolute_path to raise ArgumentError when called with the problematic path
      # But allow it to work for the root initialization
      allow(File).to receive(:absolute_path).and_call_original
      allow(File).to receive(:absolute_path).with(include("\x00"), anything).and_raise(
        ArgumentError.new('string contains null byte')
      )

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid path in coverage data', 'null byte')
      end
    end

    it 'preserves error context in JSON::ParserError messages' do
      mock_json_parse_error(JSON::ParserError.new('765: unexpected token at line 3, column 5'))

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        # Verify the original error message details are preserved
        expect(error.message).to include('765', 'line 3')
      end
    end

    it 'provides helpful error for permission issues with file path' do
      # Mock to raise permission error with actual file path
      resultset_path = File.join(root, 'coverage', '.resultset.json')
      mock_file_read_error(Errno::EACCES.new(resultset_path), path_matcher: resultset_path)

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::FilePermissionError) do |error|
        expect(error.message).to include('Permission denied')
        expect(error.message).to include('.resultset.json')
      end
    end
  end

  describe 'error context preservation' do
    it 'includes original exception message for JSON::ParserError' do
      mock_json_parse_error(JSON::ParserError.new('unexpected character at byte 42'))

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('unexpected character at byte 42')
      end
    end

    it 'includes original exception message for Errno::EACCES' do
      resultset_path = File.join(root, 'coverage', '.resultset.json')
      mock_file_read_error(Errno::EACCES.new(resultset_path), path_matcher: resultset_path)

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::FilePermissionError) do |error|
        expect(error.message).to include(resultset_path)
      end
    end

    it 'includes original exception message for TypeError' do
      # Create a malformed resultset that will cause TypeError
      malformed_resultset = {
        'RSpec' => {
          'coverage' => 'not_a_hash', # This will cause TypeError
        },
      }
      mock_resultset_data(malformed_resultset)

      expect do
        described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid coverage data structure', 'suite "RSpec"')
      end
    end
  end

  describe 'RuntimeError handling from find_resultset' do
    [
      {
        desc:      'wraps RuntimeError as UnknownError',
        error_msg: 'Specified resultset not found: /nonexistent/path/.resultset.json',
        resultset: '/nonexistent/path',
      },
      {
        desc:      'wraps RuntimeError with generic messages',
        error_msg: 'Something went wrong during resultset lookup',
        resultset: FIXTURE_PROJECT1_RESULTSET_PATH,
      },
      {
        desc:      'wraps RuntimeError without "resultset" in message',
        error_msg: 'Some completely unrelated runtime error',
        resultset: FIXTURE_PROJECT1_RESULTSET_PATH,
      },
    ].each do |tc|
      it tc[:desc] do
        allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_resultset).and_raise(
          RuntimeError.new(tc[:error_msg])
        )

        expect do
          described_class.new(root: root, resultset: tc[:resultset])
        end.to raise_error(CovLoupe::UnknownError) do |error|
          expect(error.message).to include(tc[:error_msg])
        end
      end
    end
  end

  describe 'list error handling' do
    let(:logger) { nil }
    let(:model) do
      described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH, logger: logger)
    end
    let(:foo_path) { File.expand_path('lib/foo.rb', root) }

    def stub_foo_entry_fallback
      foo_entry = model.send(:coverage_map)[foo_path]

      allow(model).to receive(:extract_lines_from_entry).and_wrap_original do |method, entry|
        entry.equal?(foo_entry) ? nil : method.call(entry)
      end
    end

    def stub_lookup_lines_error(exception_class, message)
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines).and_call_original
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
        .with(anything, foo_path, any_args)
        .and_raise(exception_class, message)
    end

    context 'when skipping rows in lenient mode' do
      let(:mock_logger) { instance_double(CovLoupe::Logger) }
      let(:logger) { mock_logger }

      before do
        stub_foo_entry_fallback
      end

      it 'skips files that raise FileError during coverage lookup' do
        expect(mock_logger).to receive(:safe_log)
          .with(a_string_including('Skipping coverage row', 'Missing file')).once

        stub_lookup_lines_error(CovLoupe::FileError, 'Missing file')

        list_result = model.list(raise_on_stale: false)
        files = list_result['files']

        # The result should contain bar.rb but not foo.rb
        file_names = files.map { |r| File.basename(r['file']) }
        expect(file_names).to include('bar.rb')
        expect(file_names).not_to include('foo.rb')
        expect(list_result['skipped_files']).to contain_exactly(
          hash_including(
            'file'        => foo_path,
            'error'       => 'Missing file',
            'error_class' => 'CovLoupe::FileError'
          )
        )
      end

      it 'skips files that raise CorruptCoverageDataError during coverage lookup' do
        expect(mock_logger).to receive(:safe_log)
          .with(a_string_including('Skipping coverage row', 'Corrupted coverage entry')).once

        stub_lookup_lines_error(CovLoupe::CorruptCoverageDataError, 'Corrupted coverage entry')

        list_result = model.list(raise_on_stale: false)
        files = list_result['files']

        file_names = files.map { |r| File.basename(r['file']) }
        expect(file_names).to include('bar.rb')
        expect(file_names).not_to include('foo.rb')
        expect(list_result['skipped_files']).to contain_exactly(
          hash_including(
            'file'        => foo_path,
            'error'       => 'Corrupted coverage entry',
            'error_class' => 'CovLoupe::CorruptCoverageDataError'
          )
        )
      end
    end

    context 'when raise_on_stale is true' do
      before do
        stub_foo_entry_fallback
      end

      it 'raises FileError when file lookup fails' do
        stub_lookup_lines_error(CovLoupe::FileError, 'Missing file')

        expect do
          model.list(raise_on_stale: true)
        end.to raise_error(CovLoupe::FileError, 'Missing file')
      end

      it 'raises CorruptCoverageDataError when data is corrupt' do
        stub_lookup_lines_error(CovLoupe::CorruptCoverageDataError, 'Corrupted coverage entry')

        expect do
          model.list(raise_on_stale: true)
        end.to raise_error(CovLoupe::CorruptCoverageDataError, 'Corrupted coverage entry')
      end
    end

    context 'when staleness checks run before data errors' do
      let(:accurate_coverage) do
        {
          File.join(root, 'lib', 'foo.rb') => { 'lines' => [nil, nil, 1, 0, nil, 2] },
          File.join(root, 'lib', 'bar.rb') => { 'lines' => [nil, nil, 0, 0, 1] },
        }
      end
      let(:resultset_timestamp) { VERY_OLD_TIMESTAMP }

      before do
        mock_resultset_with_timestamp(root, resultset_timestamp, coverage: accurate_coverage)
        stub_foo_entry_fallback
      end

      it 'checks staleness before raising data errors when raise_on_stale is true' do
        # This test verifies that staleness checking happens even when there are data errors
        # Mock File.mtime to make bar.rb appear newer than the old timestamp
        bar_path = File.expand_path('lib/bar.rb', root)
        allow(File).to receive(:mtime).and_call_original
        allow(File).to receive(:mtime).with(bar_path).and_return(Time.at(VERY_OLD_TIMESTAMP + 1000))

        stub_lookup_lines_error(CovLoupe::FileError, 'Corrupted coverage entry')

        # Should raise staleness error first (bar.rb is newer than very old timestamp)
        # not the data error from foo.rb
        expect do
          model.list(raise_on_stale: true)
        end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
          # Verify that staleness was actually detected
          expect(error.newer_files).not_to be_empty
        end
      end

      context 'when coverage is current' do
        let(:resultset_timestamp) { Time.now.to_i }

        it 'raises data error if no staleness issues when raise_on_stale is true' do
          # This test verifies that data errors ARE raised when there are no staleness issues
          stub_lookup_lines_error(CovLoupe::FileError, 'Corrupted coverage entry')

          # Should raise the data error since there are no staleness issues
          expect do
            model.list(raise_on_stale: true)
          end.to raise_error(CovLoupe::FileError, 'Corrupted coverage entry')
        end
      end
    end
  end

  describe 'resolve method error handling' do
    it 'allows FileError from lookup_lines to propagate with detailed message' do
      # Resolver raises FileError with detailed messages (e.g., basename collisions, not found)
      # The model should let these propagate to preserve helpful diagnostics
      model = described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)

      # Mock lookup_lines to raise FileError with a detailed message
      error_message = 'Multiple coverage entries match basename foo.rb: lib/foo.rb, test/foo.rb'
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
        .and_raise(CovLoupe::FileError.new(error_message))

      expect do
        model.summary_for('nonexistent_file.rb')
      end.to raise_error(CovLoupe::FileError) do |error|
        expect(error.message).to include('Multiple coverage entries match basename')
      end
    end
  end

  describe 'deleted file detection' do
    %i[summary_for raw_for uncovered_for detailed_for].each do |method|
      describe 'with raise_on_stale: false (default)' do
        it "#{method} returns coverage payload for deleted files" do
          model = described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)

          # Mock lookup_lines to return coverage data
          allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
            .and_return([1, 0, 1, nil])

          # Mock File.file? to prevent FileNotFoundError
          allow(File).to receive(:file?).and_return(false)

          result = model.send(method, 'lib/deleted_file.rb', raise_on_stale: false)

          # Should return coverage data instead of raising
          expect(result).to be_a(Hash)
          expect(result['file']).to end_with('deleted_file.rb')

          # Verify coverage-specific fields
          case method
          when :summary_for
            expect(result['summary']).to include('covered', 'total', 'percentage')
          when :raw_for
            expect(result['lines']).to eq([1, 0, 1, nil])
          when :uncovered_for
            expect(result['uncovered']).to be_an(Array)
            # summary counts non-nil elements only: [1, 0, 1, nil] => total: 3
            expect(result['summary']).to include('total' => 3)
          when :detailed_for
            expect(result['lines']).to be_an(Array)
            # summary counts non-nil elements only: [1, 0, 1, nil] => total: 3
            expect(result['summary']).to include('total' => 3)
          end

          # Verify staleness_for returns 'missing' for the file
          staleness = model.staleness_for('lib/deleted_file.rb')
          expect(staleness).to eq('missing')
        end
      end

      describe 'with raise_on_stale: true (strict mode)' do
        it "#{method} raises FileNotFoundError for deleted files" do
          model = described_class.new(root: root, resultset: FIXTURE_PROJECT1_RESULTSET_PATH)

          allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
            .and_return([1, 0, 1, nil])
          allow(File).to receive(:file?).and_return(false)

          expect do
            model.send(method, 'lib/deleted_file.rb', raise_on_stale: true)
          end.to raise_error(CovLoupe::FileNotFoundError) do |error|
            expect(error.message).to include('File not found')
          end
        end
      end
    end
  end

  describe 'malformed coverage line array validation' do
    let(:temp_resultset) { File.join(Dir.tmpdir, 'malformed_resultset.json') }
    let(:foo_path) { File.join(root, 'lib', 'foo.rb') }
    let(:bar_path) { File.join(root, 'lib', 'bar.rb') }

    def create_malformed_resultset(malformed_lines_for_foo)
      {
        'RSpec' => {
          'timestamp' => Time.now.to_i,
          'coverage'  => {
            foo_path => { 'lines' => malformed_lines_for_foo },
            bar_path => { 'lines' => [nil, nil, 0, 0, 1] },
          },
        },
      }
    end

    before do
      # Ensure source files exist
      File.write(foo_path, 'def foo; end') unless File.exist?(foo_path)
      File.write(bar_path, 'def bar; end') unless File.exist?(bar_path)
    end

    after do
      FileUtils.rm_f(temp_resultset)
    end

    %i[summary_for raw_for uncovered_for detailed_for].each do |method|
      it "#{method} raises CoverageDataError for malformed lines arrays with string elements" do
        malformed_resultset = create_malformed_resultset([1, 0, 'invalid', 2])
        File.write(temp_resultset, JSON.generate(malformed_resultset))

        model = described_class.new(root: root, resultset: temp_resultset)

        expect do
          model.send(method, 'lib/foo.rb')
        end.to raise_error(CovLoupe::CoverageDataError) do |error|
          expect(error.message).to include('Invalid coverage line array', 'non-integer elements')
        end
      end

      it "#{method} raises CoverageDataError for malformed lines arrays with float elements" do
        malformed_resultset = create_malformed_resultset([1, 0, 3.14, 2])
        File.write(temp_resultset, JSON.generate(malformed_resultset))

        model = described_class.new(root: root, resultset: temp_resultset)

        expect do
          model.send(method, 'lib/foo.rb')
        end.to raise_error(CovLoupe::CoverageDataError, /Invalid coverage line array/)
      end

      it "#{method} raises CoverageDataError for malformed lines arrays with boolean elements" do
        malformed_resultset = create_malformed_resultset([1, 0, true, 2])
        File.write(temp_resultset, JSON.generate(malformed_resultset))

        model = described_class.new(root: root, resultset: temp_resultset)

        expect do
          model.send(method, 'lib/foo.rb')
        end.to raise_error(CovLoupe::CoverageDataError, /Invalid coverage line array/)
      end

      it "#{method} raises CoverageDataError for malformed lines arrays with hash elements" do
        malformed_resultset = create_malformed_resultset([1, 0, { 'key' => 'val' }, 2])
        File.write(temp_resultset, JSON.generate(malformed_resultset))

        model = described_class.new(root: root, resultset: temp_resultset)

        expect do
          model.send(method, 'lib/foo.rb')
        end.to raise_error(CovLoupe::CoverageDataError, /Invalid coverage line array/)
      end

      it "#{method} raises CoverageDataError for malformed lines arrays with array elements" do
        malformed_resultset = create_malformed_resultset([1, 0, [1, 2], 2])
        File.write(temp_resultset, JSON.generate(malformed_resultset))

        model = described_class.new(root: root, resultset: temp_resultset)

        expect do
          model.send(method, 'lib/foo.rb')
        end.to raise_error(CovLoupe::CoverageDataError, /Invalid coverage line array/)
      end
    end

    it 'list raises CoverageDataError when raise_on_stale is true and file has malformed lines' do
      malformed_resultset = create_malformed_resultset([1, 0, 'invalid', 2])
      File.write(temp_resultset, JSON.generate(malformed_resultset))

      model = described_class.new(root: root, resultset: temp_resultset)

      expect do
        model.list(raise_on_stale: true)
      end.to raise_error(CovLoupe::CoverageDataError) do |error|
        expect(error.message).to include('Invalid coverage line array')
      end
    end

    it 'list skips files with malformed lines when raise_on_stale is false' do
      mock_logger = instance_double(CovLoupe::Logger)
      expect(mock_logger).to receive(:safe_log)
        .with(a_string_including('Skipping coverage row')).at_least(:once)

      malformed_resultset = create_malformed_resultset([1, 0, 'invalid', 2])
      File.write(temp_resultset, JSON.generate(malformed_resultset))

      model = described_class.new(root: root, resultset: temp_resultset, logger: mock_logger)

      list_result = model.list(raise_on_stale: false)
      files = list_result['files']

      file_names = files.map { |r| File.basename(r['file']) }
      expect(file_names).to include('bar.rb')
      expect(file_names).not_to include('foo.rb')
      expect(list_result['skipped_files']).to contain_exactly(
        hash_including(
          'file'        => foo_path,
          'error_class' => 'CovLoupe::CoverageDataError'
        )
      )
    end
  end
end
