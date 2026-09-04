# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageModel do
  subject(:model) { described_class.new(root: root) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  def stub_staleness_checker(
    newer_files: [], missing_files: [], deleted_files: [], length_mismatch_files: [],
    unreadable_files: [], file_statuses: {}, timestamp_status: 'ok'
  )
    checker = instance_double(
      CovLoupe::StalenessChecker,
      off?: false
    )

    allow(CovLoupe::StalenessChecker).to receive(:new).and_return(checker)
    allow(checker).to receive(:check_project_with_lines!).and_return(
      newer_files:           newer_files,
      missing_files:         missing_files,
      deleted_files:         deleted_files,
      length_mismatch_files: length_mismatch_files,
      unreadable_files:      unreadable_files,
      file_statuses:         file_statuses,
      timestamp_status:      timestamp_status
    )
  end

  describe 'initialization error handling' do
    it 'raises FileError when File.read raises Errno::ENOENT directly' do
      # Stub find_resultset to return a path, but File.read to raise ENOENT
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file)
        .and_return('/some/path/.resultset.json')
      allow(File).to receive(:read).with('/some/path/.resultset.json')
        .and_raise(Errno::ENOENT, 'No such file')

      expect do
        described_class.new(root: root, coverage_file: '/some/path/.resultset.json')
      end.to raise_error(CovLoupe::FileError, /Coverage data not found/)
    end

    it 'raises CoverageFileNotFoundError when resultset file does not exist' do
      expect do
        described_class.new(root: root, coverage_file: '/nonexistent/path/.resultset.json')
      end.to raise_error(CovLoupe::CoverageFileNotFoundError, /Specified coverage file not found/)
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
          'file'       => File.expand_path('lib/foo.rb', root),
          'percentage' => a_value_within(0.01).of(66.67)
        )
        expect(files.last).to include('file' => File.expand_path('lib/bar.rb', root))
      end

      files_asc = model.list(sort_order: :ascending)['files']
      aggregate_failures 'Ascending sort' do
        expect(files_asc.first).to include(
          'file'       => File.expand_path('lib/bar.rb', root),
          'percentage' => a_value_within(0.01).of(33.33)
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

      # Stub extract_lines_from_entry to return nil for foo.rb
      # This will trigger to resolver fallback
      # rubocop:disable RSpec/SubjectStub
      allow(model).to receive(:extract_lines_from_entry).and_wrap_original do |method, entry|
        if entry.is_a?(Hash) && entry['lines'].is_a?(Array)
          # Return nil to force resolver fallback
          nil
        else
          method.call(entry)
        end
      end
      # rubocop:enable RSpec/SubjectStub

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
          'file'        => abs_foo,
          'error'       => 'corrupt data',
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
          'total'          => 6,
          'covered'        => 3,
          'uncovered'      => 3,
          'percentage'     => be_within(0.01).of(50.0),
          'included_files' => 2,
          'excluded_files' => 0
        )
        expect(totals['tracking']).to include('enabled' => false, 'globs' => [])
        expect(totals['files']).to include('total' => 2)
        expect(totals['files']['with_coverage']).to include('total' => 2, 'ok' => 2)
      end
    end

    it 'reports stale file counts while excluding them from line totals' do
      abs_foo = File.expand_path('lib/foo.rb', root)
      abs_bar = File.expand_path('lib/bar.rb', root)

      stub_staleness_checker(
        file_statuses: {
          abs_foo => 'ok',
          abs_bar => 'newer',
        }
      )

      totals = model.project_totals

      aggregate_failures do
        expect(totals['lines']).to include(
          'total'          => 3,
          'covered'        => 2,
          'uncovered'      => 1,
          'percentage'     => be_within(0.01).of(66.67),
          'included_files' => 1,
          'excluded_files' => 1
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

      stub_staleness_checker(
        length_mismatch_files: [abs_bar],
        unreadable_files:      [abs_foo],
        file_statuses:         {
          abs_bar => 'length_mismatch',
          abs_foo => 'error',
        }
      )

      totals = model.project_totals

      aggregate_failures do
        expect(totals['lines']).to include(
          'total'          => 0,
          'covered'        => 0,
          'uncovered'      => 0,
          'percentage'     => nil,
          'included_files' => 0,
          'excluded_files' => 2
        )
        expect(totals['files']).to include('total' => 2)
        expect(totals['files']['with_coverage']['stale']).to include('total' => 2)
        expect(totals['files']['with_coverage']['stale']['by_type']).to include(
          'length_mismatch' => 1,
          'unreadable'      => 1
        )
      end
    end

    it 'respects tracked_globs filtering' do
      totals = model.project_totals(tracked_globs: ['lib/foo.rb'])

      expect(totals['lines']).to include(
        'total'      => 3,
        'covered'    => 2,
        'uncovered'  => 1,
        'percentage' => be_within(0.01).of(66.67)
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

    it 'counts unreadable tracked files in without_coverage breakdown' do
      abs_unreadable = File.expand_path('lib/unreadable.rb', root)

      stub_staleness_checker(
        unreadable_files: [abs_unreadable]
      )

      totals = model.project_totals(tracked_globs: ['lib/**/*.rb'])

      aggregate_failures do
        expect(totals['tracking']).to include('enabled' => true)
        expect(totals['files']['without_coverage']).to include('total' => 1)
        expect(totals['files']['without_coverage']['by_type'])
          .to include('unreadable' => 1)
      end
    end

    it 'increments missing_from_disk count for files with \"missing\" status' do
      abs_foo = File.expand_path('lib/foo.rb', root)

      stub_staleness_checker(
        deleted_files: [abs_foo],
        file_statuses: {
          abs_foo => 'missing',
        }
      )

      totals = model.project_totals

      expect(totals['files']['with_coverage']['stale']['by_type']).to include(
        'missing_from_disk' => 1
      )
    end
  end

  describe 'resultset directory handling' do
    it 'accepts a directory containing .resultset.json' do
      model = described_class.new(
        root:      root,
        resultset: File.dirname(FIXTURE_PROJECT1_RESULTSET_PATH)
      )
      data = model.summary_for('lib/foo.rb')
      expect(data['summary']).to include('total' => 3, 'covered' => 2)
    end
  end

  describe 'multiple suites in resultset' do
    let(:coverage_file_path) { File.join(Dir.tmpdir, 'multi_suite_resultset.json') }
    let(:shared_file) { File.join(root, 'lib', 'foo.rb') }
    let(:suite_a_cov) { { shared_file => { 'lines' => [1, 0, nil, 0] } } }
    let(:suite_b_cov) { { shared_file => { 'lines' => [0, 3, nil, 1] } } }

    let(:resultset) do
      {
        'RSpec'    => { 'timestamp' => 100, 'coverage' => suite_a_cov },
        'Cucumber' => { 'timestamp' => 200, 'coverage' => suite_b_cov },
      }
    end

    before do
      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file).and_wrap_original do
        |original, search_root, coverage_file: nil|
        is_root = File.absolute_path(search_root) == File.absolute_path(root)
        is_empty = coverage_file.nil? || coverage_file.to_s.empty?
        is_target = coverage_file.to_s == coverage_file_path

        if is_root && (is_empty || is_target)
          coverage_file_path
        else
          original.call(search_root, coverage_file: coverage_file)
        end
      end
    end

    it 'merges coverage data from multiple suites' do
      allow(File).to receive(:read).with(coverage_file_path).and_return(JSON.generate(resultset))

      model = described_class.new(root: root)

      # Check combined hits
      detailed = model.detailed_for('lib/foo.rb')
      hits_by_line = detailed['lines'].to_h { |row| [row['line'], row['hits']] }
      expect(hits_by_line).to include(1 => 1, 2 => 3, 4 => 1)
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
        custom = [{ 'file' => 'test.rb', 'percentage' => 100, 'covered' => 1, 'total' => 1,
                    'stale' => 'ok' }]
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
        off?:                      true,
        check_project_with_lines!: {
          newer_files:           [],
          missing_files:         [],
          deleted_files:         [],
          length_mismatch_files: [],
          file_statuses:         {},
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

      expect(result).to eq('error')
      expect(logger).to have_received(:safe_log).with(/Failed to check staleness/)
    end
  end

  describe 'sort tiebreaker' do
    it 'sorts by filename when percentages are equal' do
      # Create a fixture with files having identical coverage percentages
      resultset = {
        'RSpec' => {
          'timestamp' => 100,
          'coverage'  => {
            File.join(root, 'lib/alpha.rb')  => { 'lines' => [1, 0] },
            File.join(root, 'lib/zebra.rb')  => { 'lines' => [1, 0] },
            File.join(root, 'lib/middle.rb') => { 'lines' => [1, 0] },
          },
        },
      }

      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file)
        .and_return(File.join(Dir.tmpdir, 'test_resultset.json'))
      allow(File).to receive(:read).with(File.join(Dir.tmpdir, 'test_resultset.json'))
        .and_return(JSON.generate(resultset))

      test_model = described_class.new(root: root)
      files = test_model.list(sort_order: :ascending)['files']

      # All files have 50% coverage, so they should be sorted alphabetically
      file_basenames = files.map { |f| File.basename(f['file']) }
      expect(file_basenames).to eq(['alpha.rb', 'middle.rb', 'zebra.rb'])
    end
  end

  describe 'sort with nil percentage' do
    it 'sorts nil percentages after real values' do
      resultset = {
        'RSpec' => {
          'timestamp' => 100,
          'coverage'  => {
            File.join(root, 'lib/empty.rb') => { 'lines' => [] },
            File.join(root, 'lib/full.rb')  => { 'lines' => [1] },
            File.join(root, 'lib/none.rb')  => { 'lines' => [0] },
          },
        },
      }
      # empty.rb -> nil (no executable lines)
      # full.rb -> 100.0
      # none.rb -> 0.0

      allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file)
        .and_return(File.join(Dir.tmpdir, 'test_resultset.json'))
      allow(File).to receive(:read).with(File.join(Dir.tmpdir, 'test_resultset.json'))
        .and_return(JSON.generate(resultset))

      test_model = described_class.new(root: root)

      files_desc = test_model.list(sort_order: :descending)['files']
      basenames_desc = files_desc.map { |f| File.basename(f['file']) }

      expect(basenames_desc).to eq(['empty.rb', 'full.rb', 'none.rb'])

      files_asc = test_model.list(sort_order: :ascending)['files']
      basenames_asc = files_asc.map { |f| File.basename(f['file']) }

      expect(basenames_asc).to eq(['none.rb', 'full.rb', 'empty.rb'])
    end
  end

  describe '#refresh_data' do
    it 'returns self' do
      expect(model.refresh_data).to eq(model)
    end

    it 'clears resolved resultset path' do
      # Access coverage_map to trigger initial resolution
      model.send(:coverage_map)
      model.instance_variable_get(:@resolved_coverage_file_path)

      # Refresh should clear it
      model.refresh_data
      expect(model.instance_variable_get(:@resolved_coverage_file_path)).to be_nil
    end
  end

  describe 'long-lived model instance behavior' do
    let(:temp_resultset) { File.join(Dir.tmpdir, 'test_resultset.json') }
    let(:first_file_path) { File.join(root, 'lib', 'first.rb') }
    let(:second_file_path) { File.join(root, 'lib', 'second.rb') }
    let(:initial_resultset) do
      {
        'RSpec' => {
          'timestamp' => 100,
          'coverage'  => {
            first_file_path => { 'lines' => [1, 0, 1] },
          },
        },
      }
    end
    let(:updated_resultset) do
      {
        'RSpec' => {
          'timestamp' => 200,
          'coverage'  => {
            first_file_path  => { 'lines' => [1, 1, 1] },
            second_file_path => { 'lines' => [0, 0, 0] },
          },
        },
      }
    end

    before do
      # Create the source files
      FileUtils.mkdir_p(File.dirname(first_file_path))
      File.write(first_file_path, 'def foo; end')

      # Create a temporary resultset file
      File.write(temp_resultset, JSON.generate(initial_resultset))
    end

    after do
      FileUtils.rm_f(temp_resultset)
      FileUtils.rm_f(first_file_path)
      FileUtils.rm_f(second_file_path)
    end

    it 'automatically reloads data when resultset file changes' do
      # Create model with initial resultset
      long_lived_model = described_class.new(root: root, coverage_file: temp_resultset)

      # Verify initial state
      list1 = long_lived_model.list['files']
      expect(list1.map { |f| File.basename(f['file']) }).to eq(['first.rb'])
      expect(list1.first['covered']).to eq(2) # [1, 0, 1] => 2 covered

      # Create second file
      File.write(second_file_path, 'def bar; end')

      # Simulate a new test run that generates updated coverage
      # Sleep briefly to ensure timestamp change
      sleep(0.01)
      File.write(temp_resultset, JSON.generate(updated_resultset))

      # Same model instance should return updated data without refresh_data
      list2 = long_lived_model.list['files']
      expect(list2.map { |f| File.basename(f['file']) }).to eq(['first.rb', 'second.rb'])
      expect( # [1, 1, 1] => 3 covered
list2.find do |f|
  File.basename(f['file']) == 'first.rb'
end['covered']).to eq(3)
      # Verify summary_for also gets fresh data
      summary = long_lived_model.summary_for(first_file_path)
      expect(summary['summary']['covered']).to eq(3)
    end

    it 'picks up new files added to the resultset' do
      long_lived_model = described_class.new(root: root, coverage_file: temp_resultset)

      # Initial state - only first.rb exists
      files1 = long_lived_model.list['files'].map { |f| File.basename(f['file']) }
      expect(files1).to eq(['first.rb'])

      # Create the second file and update resultset
      File.write(second_file_path, 'def bar; end')
      sleep(0.01)
      File.write(temp_resultset, JSON.generate(updated_resultset))

      # Same model instance should see the new file
      files2 = long_lived_model.list['files'].map { |f| File.basename(f['file']) }
      expect(files2).to contain_exactly('first.rb', 'second.rb')
    end
  end

  describe 'Errno::ENOENT handling in coverage_data_for' do
    let(:existing_file) { 'lib/foo.rb' }
    let(:existing_file_abs) { File.expand_path(existing_file, root) }
    let(:mock_logger) { instance_double(CovLoupe::Logger, safe_log: true) }

    it 'returns [file_abs, coverage_lines] when staleness checker raises ' \
      'Errno::ENOENT with raise_on_stale: false' do
      # Create a model with a custom logger to allow stubbing
      model_with_logger = described_class.new(root: root, logger: mock_logger)

      # Stub build_staleness_checker to return a checker that raises Errno::ENOENT
      fake_checker = instance_double(CovLoupe::StalenessChecker, off?: false)
      allow(fake_checker).to receive(:check_file!).with(existing_file_abs, anything)
        .and_raise(Errno::ENOENT, 'No such file or directory')

      allow(model_with_logger).to receive(:build_staleness_checker).and_return(fake_checker)

      # The coverage_data_for method should return the tuple without raising
      file_abs, coverage_lines = model_with_logger.send(:coverage_data_for, existing_file,
        raise_on_stale: false)

      expect(file_abs).to eq(existing_file_abs)
      expect(coverage_lines).to be_an(Array)
    end

    it 'raises FileNotFoundError when staleness checker raises Errno::ENOENT with raise_on_stale: true' do
      model_with_logger = described_class.new(root: root, logger: mock_logger, raise_on_stale: true)

      # Stub build_staleness_checker to return a checker that raises Errno::ENOENT
      fake_checker = instance_double(CovLoupe::StalenessChecker, off?: false)
      allow(fake_checker).to receive(:check_file!).with(existing_file_abs, anything)
        .and_raise(Errno::ENOENT, 'No such file or directory')

      allow(model_with_logger).to receive(:build_staleness_checker).and_return(fake_checker)

      expect do
        model_with_logger.send(:coverage_data_for, existing_file, raise_on_stale: true)
      end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)
    end

    it 'returns coverage payload via summary_for when staleness checker ' \
      'raises Errno::ENOENT with raise_on_stale: false' do
      model_with_logger = described_class.new(root: root, logger: mock_logger)

      # Stub build_staleness_checker to return a checker that raises Errno::ENOENT
      fake_checker = instance_double(CovLoupe::StalenessChecker, off?: false)
      allow(fake_checker).to receive(:check_file!).with(existing_file_abs, anything)
        .and_raise(Errno::ENOENT, 'No such file or directory')

      allow(model_with_logger).to receive(:build_staleness_checker).and_return(fake_checker)

      # summary_for should return coverage data without raising
      result = model_with_logger.summary_for(existing_file, raise_on_stale: false)

      expect(result).to include(
        'file'    => existing_file_abs,
        'summary' => be_a(Hash)
      )
    end
  end

  describe '#extract_lines_from_entry' do
    let(:mock_logger) { instance_double(CovLoupe::Logger, safe_log: true) }
    let(:model_with_logger) { described_class.new(root: root, logger: mock_logger) }

    it 'returns nil for entries with non-integer/nil values in lines array (triggers resolver fallback)' do
      bad_entry = { 'lines' => ['foo', 3.5, {}, nil] }

      # extract_lines_from_entry silently returns nil to trigger resolver fallback
      # The resolver will perform centralized validation and raise CoverageDataError
      expect(model_with_logger.send(:extract_lines_from_entry, bad_entry)).to be_nil
    end

    it 'returns array for valid entries' do
      good_entry = { 'lines' => [1, 0, nil, 2] }
      expect(model_with_logger.send(:extract_lines_from_entry, good_entry)).to eq([1, 0, nil, 2])
    end

    it 'returns nil and logs warning when lines is not an array' do
      bad_entry = { 'lines' => 'not an array' }

      expect(mock_logger).to receive(:safe_log)
        .with(/Invalid coverage lines encountered \(not an array\)/)
      expect(model_with_logger.send(:extract_lines_from_entry, bad_entry)).to be_nil
    end
  end

  describe 'missing file handling with raise_on_stale' do
    let(:temp_resultset) { File.join(Dir.tmpdir, 'test_missing_file_resultset.json') }
    let(:missing_file_path) { File.join(root, 'lib', 'deleted.rb') }
    let(:resultset_with_deleted_file) do
      {
        'RSpec' => {
          'timestamp' => 100,
          'coverage'  => {
            missing_file_path => { 'lines' => [1, 0, 1] },
          },
        },
      }
    end

    before do
      # Ensure the file doesn't exist but is in the resultset
      FileUtils.rm_f(missing_file_path)
      File.write(temp_resultset, JSON.generate(resultset_with_deleted_file))
    end

    after do
      FileUtils.rm_f(temp_resultset)
      FileUtils.rm_f(missing_file_path)
    end

    describe 'with raise_on_stale: false (default)' do
      it 'returns coverage payload for missing file' do
        model_with_deleted = described_class.new(root: root, coverage_file: temp_resultset)

        # All single-file methods should return coverage data
        aggregate_failures do
          # summary_for
          summary = model_with_deleted.summary_for('lib/deleted.rb')
          expect(summary).to include(
            'file'    => missing_file_path,
            'summary' => include('total' => 3, 'covered' => 2)
          )

          # detailed_for
          detailed = model_with_deleted.detailed_for('lib/deleted.rb')
          expect(detailed).to include(
            'file'    => missing_file_path,
            'lines'   => be_an(Array),
            'summary' => include('total' => 3)
          )

          # raw_for
          raw = model_with_deleted.raw_for('lib/deleted.rb')
          expect(raw).to include(
            'file'  => missing_file_path,
            'lines' => [1, 0, 1]
          )

          # uncovered_for
          uncovered = model_with_deleted.uncovered_for('lib/deleted.rb')
          expect(uncovered).to include(
            'file'      => missing_file_path,
            'uncovered' => [2],
            'summary'   => include('total' => 3)
          )
        end
      end

      it 'reports staleness status for missing file via staleness_for' do
        model_with_deleted = described_class.new(root: root, coverage_file: temp_resultset)

        staleness = model_with_deleted.staleness_for('lib/deleted.rb')
        expect(staleness).to eq('missing')
      end
    end

    describe 'with raise_on_stale: true (strict mode)' do
      it 'raises FileNotFoundError for missing file' do
        strict_model = described_class.new(
          root:           root,
          resultset:      temp_resultset,
          raise_on_stale: true
        )

        # All single-file methods should raise
        aggregate_failures do
          expect do
            strict_model.summary_for('lib/deleted.rb')
          end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)

          expect do
            strict_model.detailed_for('lib/deleted.rb')
          end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)

          expect do
            strict_model.raw_for('lib/deleted.rb')
          end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)

          expect do
            strict_model.uncovered_for('lib/deleted.rb')
          end.to raise_error(CovLoupe::FileNotFoundError, /File not found/)
        end
      end

      it 'returns staleness status without raising via staleness_for' do
        strict_model = described_class.new(
          root:           root,
          resultset:      temp_resultset,
          raise_on_stale: true
        )

        # staleness_for uses raise_on_stale: false internally
        staleness = strict_model.staleness_for('lib/deleted.rb')
        expect(staleness).to eq('missing')
      end
    end

    describe 'existing file behavior unchanged' do
      let(:existing_file_path) { File.join(root, 'lib', 'existing.rb') }
      let(:resultset_timestamp) { Time.now.to_i }
      let(:resultset_with_existing_file) do
        {
          'RSpec' => {
            'timestamp' => resultset_timestamp,
            'coverage'  => {
              existing_file_path => { 'lines' => [1, 1, 0] },
            },
          },
        }
      end

      before do
        FileUtils.mkdir_p(File.dirname(existing_file_path))
        # Create file with 3 lines to match resultset coverage
        File.write(existing_file_path, <<~RUBY)
          def existing
            'line 2'
            'line 3'
          end
        RUBY
        # Set file mtime to be older than resultset timestamp to avoid staleness
        File.utime(resultset_timestamp - 10, resultset_timestamp - 10, existing_file_path)
        # Sleep to ensure resultset timestamp is after file mtime
        sleep(0.01)
        File.write(temp_resultset, JSON.generate(resultset_with_existing_file))
      end

      after do
        FileUtils.rm_f(temp_resultset)
        FileUtils.rm_f(existing_file_path)
      end

      it 'works normally for existing files regardless of raise_on_stale' do
        # Mock staleness checker to return OK status
        stub_checker = instance_double(CovLoupe::StalenessChecker, off?: true)
        allow(CovLoupe::StalenessChecker).to receive(:new).and_return(stub_checker)
        allow(stub_checker).to receive(:check_file!).and_return(nil)

        aggregate_failures do
          # Default (raise_on_stale: false)
          normal_model = described_class.new(root: root, coverage_file: temp_resultset)
          summary = normal_model.summary_for('lib/existing.rb')
          expect(summary).to include('summary' => include('total' => 3, 'covered' => 2))

          # Strict (raise_on_stale: true)
          strict_model = described_class.new(
            root:           root,
            resultset:      temp_resultset,
            raise_on_stale: true
          )
          summary_strict = strict_model.summary_for('lib/existing.rb')
          expect(summary_strict).to include('summary' => include('total' => 3, 'covered' => 2))
        end
      end
    end
  end
end
