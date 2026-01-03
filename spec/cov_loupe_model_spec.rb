# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageModel do
  subject(:model) { described_class.new(root: root) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  describe 'initialization error handling' do
    it 'raises FileError when File.read raises Errno::ENOENT directly' do
      # Stub find_resultset to return a path, but File.read to raise ENOENT
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_resultset)
        .and_return('/some/path/.resultset.json')
      allow(File).to receive(:read).with('/some/path/.resultset.json')
        .and_raise(Errno::ENOENT, 'No such file')

      expect do
        described_class.new(root: root, resultset: '/some/path/.resultset.json')
      end.to raise_error(CovLoupe::FileError, /Coverage data not found/)
    end

    it 'raises ResultsetNotFoundError when resultset file does not exist' do
      expect do
        described_class.new(root: root, resultset: '/nonexistent/path/.resultset.json')
      end.to raise_error(CovLoupe::ResultsetNotFoundError, /Specified resultset not found/)
    end
  end

  describe 'resolve method error handling' do
    it 'raises FileError when lookup_lines returns nil' do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines).and_return(nil)

      expect do
        model.summary_for('lib/nonexistent.rb')
      end.to raise_error(CovLoupe::FileError, /No coverage data found for file/)
    end

    it 'allows FileError from lookup_lines to propagate' do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
        .and_raise(CovLoupe::FileError, 'No coverage entry found for lib/some_file.rb')

      expect do
        model.summary_for('lib/some_file.rb')
      end.to raise_error(CovLoupe::FileError, /No coverage entry found/)
    end

    it 'raises FileNotFoundError when check_file! raises ENOENT' do
      checker = instance_double(CovLoupe::StalenessChecker, off?: false)
      allow(CovLoupe::StalenessChecker).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_file!)
        .and_raise(Errno::ENOENT, 'No such file or directory')

      stale_model = described_class.new(root: root, raise_on_stale: true)

      expect do
        stale_model.summary_for('lib/foo.rb')
      end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)
    end
  end

  describe 'list' do
    def stub_staleness_checker(
      newer_files: [], missing_files: [], deleted_files: [], length_mismatch_files: [],
      unreadable_files: [], file_statuses: {}
    )
      checker = instance_double(
        CovLoupe::StalenessChecker,
        off?: false
      )

      allow(CovLoupe::StalenessChecker).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_project_with_lines!).and_return(
        newer_files: newer_files,
        missing_files: missing_files,
        deleted_files: deleted_files,
        length_mismatch_files: length_mismatch_files,
        unreadable_files: unreadable_files,
        file_statuses: file_statuses
      )
    end

    it 'returns a hash with correct keys' do
      result = model.list
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        'files', 'skipped_files', 'missing_tracked_files', 'newer_files', 'deleted_files',
        'length_mismatch_files', 'unreadable_files', 'timestamp_status'
      )
      expect(result['timestamp_status']).to be_a(Symbol).or be_a(String)
      result.except('timestamp_status').each_value { |v| expect(v).to be_a(Array) }
    end

    it 'sorts files correctly' do
      files = model.list['files']
      aggregate_failures 'Descending sort' do
        expect(files.first).to include(
          'file' => File.expand_path('lib/foo.rb', root),
          'percent_covered' => a_value_within(0.01).of(66.67)
        )
        expect(files.last).to include('file' => File.expand_path('lib/bar.rb', root))
      end

      files_asc = model.list(sort_order: :ascending)['files']
      aggregate_failures 'Ascending sort' do
        expect(files_asc.first).to include(
          'file' => File.expand_path('lib/bar.rb', root),
          'percent_covered' => a_value_within(0.01).of(33.33)
        )
        expect(files_asc.last).to include('file' => File.expand_path('lib/foo.rb', root))
      end
    end

    it 'filters rows when tracked_globs are provided' do
      abs_foo = File.expand_path('lib/foo.rb', root)
      abs_bar = File.expand_path('lib/bar.rb', root)

      aggregate_failures do
        # Single glob
        files = model.list(tracked_globs: ['lib/foo.rb'])['files']
        expect(files.length).to eq(1)
        expect(files.first['file']).to eq(abs_foo)

        # Multiple globs
        files_multi = model.list(tracked_globs: ['lib/foo.rb', abs_bar])['files']
        expect(files_multi.map { |f| f['file'] }).to contain_exactly(abs_foo, abs_bar)

        # Absolute pattern
        files_abs = model.list(tracked_globs: [abs_foo])['files']
        expect(files_abs.map { |f| f['file'] }).to contain_exactly(abs_foo)
      end
    end

    it 'records skipped rows when coverage data errors occur' do
      abs_foo = File.expand_path('lib/foo.rb', root)

      # Make the entry malformed for foo.rb so it falls back to the resolver
      cov = model.instance_variable_get(:@cov)
      cov[abs_foo] = 'malformed_entry' # Not a Hash with 'lines' key

      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines).and_wrap_original do
        |method, coverage_map, absolute, **kwargs|
        if absolute == abs_foo
          raise(CovLoupe::CoverageDataError, 'corrupt data')
        else
          method.call(coverage_map, absolute, **kwargs)
        end
      end

      result = model.list

      expect(result['files'].map { |row| row['file'] }).not_to include(abs_foo)

      expect(result['skipped_files']).to contain_exactly(
        hash_including(
          'file' => abs_foo,
          'error' => 'corrupt data',
          'error_class' => 'CovLoupe::CoverageDataError'
        )
      )
    end

    it 'reports newer_files' do
      newer_file = File.expand_path('lib/foo.rb', root)

      stub_staleness_checker(newer_files: [newer_file])

      result = model.list

      expect(result['newer_files']).to contain_exactly(newer_file)
    end

    it 'reports deleted_files' do
      deleted_file = 'lib/bar.rb'

      stub_staleness_checker(deleted_files: [deleted_file])

      result = model.list

      expect(result['deleted_files']).to include(deleted_file)
    end
  end

  describe '#project_totals' do
    it 'aggregates coverage totals across all files' do
      totals = model.project_totals

      aggregate_failures do
        expect(totals['lines']).to include(
          'total' => 6,
          'covered' => 3,
          'uncovered' => 3,
          'percent_covered' => be_within(0.01).of(50.0)
        )
        expect(totals['tracking']).to include('enabled' => false, 'globs' => [])
        expect(totals['files']).to include('total' => 2)
        expect(totals['files']['with_coverage']).to include('total' => 2, 'ok' => 2)
      end
    end

    it 'reports stale file counts while excluding them from line totals' do
      abs_foo = File.expand_path('lib/foo.rb', root)
      abs_bar = File.expand_path('lib/bar.rb', root)

      checker = instance_double(CovLoupe::StalenessChecker)
      allow(CovLoupe::StalenessChecker).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_project_with_lines!).and_return(
        newer_files: [],
        missing_files: [],
        deleted_files: [],
        length_mismatch_files: [],
        unreadable_files: [],
        file_statuses: {
          abs_foo => false,
          abs_bar => 'T'
        }
      )

      totals = model.project_totals

      aggregate_failures do
        expect(totals['lines']).to include(
          'total' => 3,
          'covered' => 2,
          'uncovered' => 1,
          'percent_covered' => be_within(0.01).of(66.67)
        )
        expect(totals['files']).to include('total' => 2)
        expect(totals['files']['with_coverage']).to include('total' => 2, 'ok' => 1)
        expect(totals['files']['with_coverage']['stale']).to include('total' => 1)
        expect(totals['files']['with_coverage']['stale']['by_type']).to include('newer' => 1)
      end
    end

    it 'excludes stale rows from totals and reports length/unreadable exclusions' do
      abs_foo = File.expand_path('lib/foo.rb', root)
      abs_bar = File.expand_path('lib/bar.rb', root)

      checker = instance_double(CovLoupe::StalenessChecker)
      allow(CovLoupe::StalenessChecker).to receive(:new).and_return(checker)
      allow(checker).to receive(:check_project_with_lines!).and_return(
        newer_files: [],
        missing_files: [],
        deleted_files: [],
        length_mismatch_files: [abs_bar],
        unreadable_files: [abs_foo],
        file_statuses: {
          abs_bar => 'L',
          abs_foo => 'E'
        }
      )

      totals = model.project_totals

      aggregate_failures do
        expect(totals['lines']).to include(
          'total' => 0,
          'covered' => 0,
          'uncovered' => 0,
          'percent_covered' => 100.0
        )
        expect(totals['files']).to include('total' => 2)
        expect(totals['files']['with_coverage']['stale']).to include('total' => 2)
        expect(totals['files']['with_coverage']['stale']['by_type']).to include(
          'length_mismatch' => 1,
          'unreadable' => 1
        )
      end
    end

    it 'respects tracked_globs filtering' do
      totals = model.project_totals(tracked_globs: ['lib/foo.rb'])

      expect(totals['lines']).to include(
        'total' => 3,
        'covered' => 2,
        'uncovered' => 1,
        'percent_covered' => be_within(0.01).of(66.67)
      )
      expect(totals['tracking']).to include('enabled' => true, 'globs' => ['lib/foo.rb'])
      expect(totals['files']).to include('total' => 1)
      expect(totals['files']['with_coverage']).to include('total' => 1, 'ok' => 1)
    end

    it 'includes without_coverage data when tracking is enabled' do
      totals = model.project_totals(tracked_globs: ['lib/**/*.rb'])

      expect(totals['tracking']).to include('enabled' => true)
      expect(totals['files']['without_coverage']).to include('total' => 1)
      expect(totals['files']['without_coverage']['by_type'])
        .to include('missing_from_coverage' => 1)
    end
  end

  describe 'resultset directory handling' do
    it 'accepts a directory containing .resultset.json' do
      model = described_class.new(
        root: root,
        resultset: File.dirname(FIXTURE_PROJECT1_RESULTSET_PATH)
      )
      data = model.summary_for('lib/foo.rb')
      expect(data['summary']).to include('total' => 3, 'covered' => 2)
    end
  end

  describe 'multiple suites in resultset' do
    let(:resultset_path) { '/tmp/multi_suite_resultset.json' }
    let(:shared_file) { File.join(root, 'lib', 'foo.rb') }
    let(:suite_a_cov) { { shared_file => { 'lines' => [1, 0, nil, 0] } } }
    let(:suite_b_cov) { { shared_file => { 'lines' => [0, 3, nil, 1] } } }

    let(:resultset) do
      {
        'RSpec' => { 'timestamp' => 100, 'coverage' => suite_a_cov },
        'Cucumber' => { 'timestamp' => 200, 'coverage' => suite_b_cov }
      }
    end

    before do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_resultset).and_wrap_original do
        |original, search_root, resultset: nil|
        is_root = File.absolute_path(search_root) == File.absolute_path(root)
        is_empty = resultset.nil? || resultset.to_s.empty?

        if is_root && is_empty
          resultset_path
        else
          original.call(search_root, resultset: resultset)
        end
      end
    end

    it 'merges coverage data and keeps latest timestamp' do
      allow(File).to receive(:read).with(resultset_path).and_return(JSON.generate(resultset))

      model = described_class.new(root: root)

      aggregate_failures do
        # Check combined hits
        detailed = model.detailed_for('lib/foo.rb')
        hits_by_line = detailed['lines'].to_h { |row| [row['line'], row['hits']] }
        expect(hits_by_line).to include(1 => 1, 2 => 3, 4 => 1)

        # Check timestamp
        timestamp = model.instance_variable_get(:@cov_timestamp)
        expect(timestamp).to eq(200)
      end
    end
  end

  describe 'format_table' do
    it 'delegates to CoverageTableFormatter for formatting' do
      expect(CovLoupe::CoverageTableFormatter).to receive(:format).and_call_original
      model.format_table
    end

    it 'formats and sorts table correctly' do
      list_data = model.list['files']

      aggregate_failures do
        # Default sort
        output = model.format_table
        expect(output).to include('lib/foo.rb', 'lib/bar.rb')

        # Empty rows
        expect(model.format_table([])).to eq('No coverage data found')

        # Custom rows
        custom = [{ 'file' => 'test.rb', 'percent_covered' => 100, 'covered' => 1, 'total' => 1,
                    'stale' => false }]
        expect(model.format_table(custom)).to include('test.rb')

        # Sorting: Ascending (bar before foo)
        output_asc = model.format_table(list_data, sort_order: :ascending)
        expect(output_asc.index('bar.rb')).to be < output_asc.index('foo.rb')

        # Sorting: Descending (foo before bar)
        output_desc = model.format_table(list_data, sort_order: :descending)
        expect(output_desc.index('foo.rb')).to be < output_desc.index('bar.rb')
      end
    end
  end

  describe 'default tracked_globs' do
    let(:tracked_globs) { ['lib/foo.rb'] }
    let(:model_with_globs) { described_class.new(root: root, tracked_globs: tracked_globs) }

    it 'uses constructor tracked_globs for operations' do
      # Setup for list
      allow(model_with_globs).to receive(:filter_rows_by_globs).and_call_original
      stub_checker = instance_double(
        CovLoupe::StalenessChecker,
        off?: true,
        check_project_with_lines!: {
          newer_files: [],
          missing_files: [],
          deleted_files: [],
          length_mismatch_files: [],
          file_statuses: {}
        }
      )
      allow(model_with_globs).to receive(:build_staleness_checker).and_return(stub_checker)

      aggregate_failures do
        # List
        model_with_globs.list
        # filter_rows_by_globs is called twice: once for files, once for skipped_files
        expect(model_with_globs).to have_received(:filter_rows_by_globs)
          .with(anything, tracked_globs).twice

        # Project totals (delegates to list with globs)
        expect(model_with_globs).to receive(:list)
          .with(hash_including(tracked_globs: tracked_globs))
          .and_call_original
        model_with_globs.project_totals

        # Format table
        allow(model_with_globs).to receive(:prepare_rows).and_return([])
        model_with_globs.format_table
        expect(model_with_globs).to have_received(:prepare_rows)
          .with(anything, hash_including(tracked_globs: tracked_globs))
      end
    end
  end

  describe '#staleness_for' do
    it "returns 'E' marker and logs error when staleness check fails" do
      logger = instance_double(CovLoupe::Logger)
      allow(CovLoupe).to receive(:logger).and_return(logger)
      allow(logger).to receive(:safe_log)

      model_with_logger = described_class.new(root: root, logger: logger)

      # Make lookup_lines raise an error
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
        .and_raise(StandardError, 'Test error')

      result = model_with_logger.staleness_for('lib/foo.rb')

      expect(result).to eq('E')
      expect(logger).to have_received(:safe_log).with(/Failed to check staleness/)
    end
  end

  describe 'sort tiebreaker' do
    it 'sorts by filename when percentages are equal' do
      # Create a fixture with files having identical coverage percentages
      resultset = {
        'RSpec' => {
          'timestamp' => 100,
          'coverage' => {
            File.join(root, 'lib/alpha.rb') => { 'lines' => [1, 0] },
            File.join(root, 'lib/zebra.rb') => { 'lines' => [1, 0] },
            File.join(root, 'lib/middle.rb') => { 'lines' => [1, 0] }
          }
        }
      }

      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_resultset)
        .and_return('/tmp/test_resultset.json')
      allow(File).to receive(:read).with('/tmp/test_resultset.json')
        .and_return(JSON.generate(resultset))

      test_model = described_class.new(root: root)
      files = test_model.list(sort_order: :ascending)['files']

      # All files have 50% coverage, so they should be sorted alphabetically
      file_basenames = files.map { |f| File.basename(f['file']) }
      expect(file_basenames).to eq(['alpha.rb', 'middle.rb', 'zebra.rb'])
    end
  end
end
