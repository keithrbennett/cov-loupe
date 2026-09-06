# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe CovLoupe::CoverageModel do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  it "raises stale error when staleness mode is 'error' and file is newer" do
    mock_resultset_with_timestamp(root, VERY_OLD_TIMESTAMP)
    model = described_class.new(root: root, raise_on_stale: true)
    expect do
      model.summary_for('lib/foo.rb')
    end.to raise_error(CovLoupe::CoverageDataStaleError, /stale/i)
  end

  it "does not check staleness when mode is 'off'" do
    mock_resultset_with_timestamp(root, VERY_OLD_TIMESTAMP)
    model = described_class.new(root: root, raise_on_stale: false)
    expect { model.summary_for('lib/foo.rb') }.not_to raise_error
  end

  it 'list raises project-level stale when any source file is newer than coverage' do
    mock_resultset_with_timestamp(root, VERY_OLD_TIMESTAMP)
    model = described_class.new(root: root, raise_on_stale: true)
    expect { model.list }.to raise_error(CovLoupe::CoverageDataProjectStaleError)
  end

  it 'list detects new files via tracked_globs' do
    mock_resultset_with_timestamp(root, Time.now.to_i)
    Tempfile.create(%w[brand_new_file .rb], File.join(root, 'lib')) do |f|
      f.write("# new file\n")
      f.flush
      model = described_class.new(root: root, raise_on_stale: true)
      expect do
        model.list(tracked_globs: %w[lib/**/*.rb])
      end.to raise_error(CovLoupe::CoverageDataProjectStaleError)
    end
  end

  describe 'tracked_globs scoping for staleness checks' do
    it 'only reports newer_files that match tracked_globs' do
      # Use coverage data with correct line counts (foo.rb: 6 lines, bar.rb: 5 lines)
      accurate_coverage = {
        File.join(root, 'lib', 'foo.rb') => { 'lines' => [nil, nil, 1, 0, nil, 2] },
        File.join(root, 'lib', 'bar.rb') => { 'lines' => [nil, nil, 0, 0, 1] },
      }
      mock_resultset_with_timestamp(root, VERY_OLD_TIMESTAMP, coverage: accurate_coverage)

      # All files are newer than the very old timestamp, but we're only tracking lib/foo.rb
      model = described_class.new(root: root, raise_on_stale: false)
      result = model.list(tracked_globs: ['lib/foo.rb'])

      # Should only report foo.rb as newer, not bar.rb (which is also newer but outside scope)
      expect(result['newer_files']).to eq(['lib/foo.rb'])
      expect(result['newer_files']).not_to include('lib/bar.rb')
    end

    it 'only reports deleted_files that match tracked_globs' do
      # Create a scenario where bar.rb is in coverage but missing from filesystem
      coverage_with_missing = {
        File.join(root, 'lib', 'foo.rb')         => { 'lines' => [1, 0, nil, 2] },
        File.join(root, 'lib', 'bar.rb')         => { 'lines' => [0, 0, 1] },
        File.join(root, 'lib', 'nonexistent.rb') => { 'lines' => [1, 1] },
      }
      mock_resultset_with_timestamp(root, Time.now.to_i, coverage: coverage_with_missing)

      model = described_class.new(root: root, raise_on_stale: false)
      result = model.list(tracked_globs: ['lib/foo.rb'])

      # Should not report nonexistent.rb as deleted since it's outside tracked_globs scope
      expect(result['deleted_files']).to eq([])
      expect(result['deleted_files']).not_to include('lib/nonexistent.rb')
    end

    it 'includes all stale files when tracked_globs is not specified' do
      # Use coverage data with correct line counts (foo.rb: 6 lines, bar.rb: 5 lines)
      accurate_coverage = {
        File.join(root, 'lib', 'foo.rb') => { 'lines' => [nil, nil, 1, 0, nil, 2] },
        File.join(root, 'lib', 'bar.rb') => { 'lines' => [nil, nil, 0, 0, 1] },
      }
      mock_resultset_with_timestamp(root, VERY_OLD_TIMESTAMP, coverage: accurate_coverage)

      model = described_class.new(root: root, raise_on_stale: false)
      result = model.list

      # Should report both files as newer when no filtering is applied
      expect(result['newer_files']).to include('lib/foo.rb', 'lib/bar.rb')
    end

    it 'only checks length mismatches for files matching tracked_globs' do
      # Create coverage with length mismatch for bar.rb (actual: 5 lines, coverage: 2 lines)
      # and accurate coverage for foo.rb (actual: 6 lines, coverage: 6 lines)
      mismatched_coverage = {
        File.join(root, 'lib', 'foo.rb') => { 'lines' => [nil, nil, 1, 0, nil, 2] },
        File.join(root, 'lib', 'bar.rb') => { 'lines' => [0, 0] }, # Wrong length!
      }
      mock_resultset_with_timestamp(root, Time.now.to_i, coverage: mismatched_coverage)

      # Only track foo.rb - bar.rb's length mismatch should be ignored
      model = described_class.new(root: root, raise_on_stale: false)
      result = model.list(tracked_globs: ['lib/foo.rb'])

      # bar.rb should not appear in the results at all since it's outside tracked_globs
      expect(result['files'].map { |f| f['file'] }).to eq([File.join(root, 'lib', 'foo.rb')])
      # foo.rb should not be marked as stale (no mismatch, and timestamp is current)
      foo_row = result['files'].find { |f| f['file'] == File.join(root, 'lib', 'foo.rb') }
      expect(foo_row['stale']).to eq('ok')
    end

    it 'raises error for length mismatch only when file is in tracked_globs scope' do
      # Create coverage with length mismatch for bar.rb (actual: 5 lines, coverage: 2 lines)
      # and accurate coverage for foo.rb (actual: 6 lines, coverage: 6 lines)
      mismatched_coverage = {
        File.join(root, 'lib', 'foo.rb') => { 'lines' => [nil, nil, 1, 0, nil, 2] },
        File.join(root, 'lib', 'bar.rb') => { 'lines' => [0, 0] }, # Wrong length!
      }
      mock_resultset_with_timestamp(root, Time.now.to_i, coverage: mismatched_coverage)

      # When tracking only foo.rb with raise_on_stale, bar.rb's mismatch should be ignored
      model = described_class.new(root: root, raise_on_stale: true)
      expect { model.list(tracked_globs: ['lib/foo.rb']) }.not_to raise_error

      # When tracking bar.rb with raise_on_stale, the length mismatch should raise
      expect do
        model.list(tracked_globs: ['lib/bar.rb'])
      end.to raise_error(CovLoupe::CoverageDataProjectStaleError) { |error|
        expect(error.length_mismatch_files).to include('lib/bar.rb')
      }
    end

    context 'with skipped files' do
      let(:foo_path) { File.join(root, 'lib', 'foo.rb') }
      let(:bar_path) { File.join(root, 'lib', 'bar.rb') }
      let(:baz_path) { File.join(root, 'lib', 'baz.rb') }
      let(:coverage_with_errors) do
        {
          foo_path => { 'lines' => [nil, nil, 1, 0, nil, 2] },  # Valid
          bar_path => 'not_a_hash',  # Malformed - will be skipped
          baz_path => 'also_malformed',  # Malformed - will be skipped
        }
      end

      before do
        mock_resultset_with_timestamp(root, Time.now.to_i, coverage: coverage_with_errors)
      end

      it 'only includes skipped files that match tracked_globs' do
        model = described_class.new(root: root, raise_on_stale: false)
        result = model.list(tracked_globs: ['lib/foo.rb', 'lib/bar.rb'])

        expect(result['skipped_files'].map { |f| f['file'] }).to eq([bar_path])
        expect(result['skipped_files']).not_to include(hash_including('file' => baz_path))
      end

      it 'includes all skipped files when tracked_globs is not specified' do
        model = described_class.new(root: root, raise_on_stale: false)
        result = model.list

        skipped_paths = result['skipped_files'].map { |f| f['file'] }
        expect(skipped_paths).to include(bar_path, baz_path)
        expect(skipped_paths.length).to eq(2)
      end
    end
  end

  describe 'timestamp normalization' do
    it 'parses created_at strings to epoch seconds' do
      created_at = Time.new(2024, 7, 3, 16, 26, 40, '-07:00')
      mock_resultset_with_created_at(root, created_at.strftime('%Y-%m-%d %H:%M:%S %z'))

      model = described_class.new(root: root, raise_on_stale: false)

      # Verify that the timestamp is correctly parsed by checking staleness behavior
      # When coverage timestamp is in the past and file is newer, it should be stale
      # Since created_at is in 2024 and files are current, they should be newer
      foo_path = File.join(root, 'lib', 'foo.rb')

      # Make coverage older than file by mocking file mtime to be newer
      current_time = Time.now
      allow(File).to receive(:mtime).and_wrap_original do |m, path|
        path.to_s == foo_path ? current_time : m.call(path)
      end

      # With raise_on_stale: true, should raise because file is newer
      expect do
        model.summary_for('lib/foo.rb', raise_on_stale: true)
      end.to raise_error(CovLoupe::CoverageDataStaleError, /stale/i)
    end

    it 'propagates parsed created_at timestamps into stale errors' do
      file_mtime = File.mtime(File.join(root, 'lib', 'foo.rb'))
      created_at_time = (file_mtime + 3600).utc
      # Use mismatched coverage (3 lines instead of 4) to trigger staleness
      mismatched_coverage = {
        File.join(root, 'lib', 'foo.rb') => { 'lines' => [1, 0, nil] },
      }
      mock_resultset_with_created_at(root, created_at_time.iso8601, coverage: mismatched_coverage)

      model = described_class.new(root: root, raise_on_stale: true)

      expect do
        model.summary_for('lib/foo.rb')
      end.to raise_error(CovLoupe::CoverageDataStaleError) { |error|
        # Verify the error includes coverage timestamp information
        expect(error.cov_timestamp).to eq(created_at_time.to_i)
      }
    end
  end

  it 'raises file-level stale when source and coverage lengths differ' do
    # Ensure time is not the triggering factor - use current timestamp
    mock_resultset_with_timestamp(root, Time.now.to_i, coverage: {
      File.join(root, 'lib', 'bar.rb') => { 'lines' => [1, 1] }, # 2 entries vs 3 lines in source
    })
    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)
    # bar.rb has 2 coverage entries but 3 source lines in fixtures
    expect do
      model.summary_for('lib/bar.rb')
    end.to raise_error(CovLoupe::CoverageDataStaleError, /stale/i)
  end

  it 'raises on list when source and coverage lengths differ' do
    mock_resultset_with_timestamp(root, Time.now.to_i, coverage: {
      File.join(root, 'lib', 'bar.rb') => { 'lines' => [1, 1] }, # 2 entries vs 3 lines in source
    })
    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError, /stale/i)
  end

  it 'raises on list when file is newer than coverage but line count matches' do
    # Create coverage with an old timestamp (1 hour ago)
    old_timestamp = Time.now.to_i - 3600
    bar_path = File.join(root, 'lib', 'bar.rb')
    # Use current time for file mtime to ensure it is newer
    current_time = Time.now

    mock_resultset_with_timestamp(root, old_timestamp, coverage: {
      # 5 lines to match actual bar.rb
      bar_path => { 'lines' => [nil, nil, 1, 0, 1] },
    })

    # Stub mtime to simulate file being newer than coverage
    allow(File).to receive(:mtime).and_wrap_original do |m, path|
      path.to_s == bar_path ? current_time : m.call(path)
    end

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
      expect(error.newer_files).to include('lib/bar.rb')
    end
  end

  it 'does not raise when all files are up to date with matching line counts' do
    # Create coverage with future timestamp and matching line counts
    # Use future timestamp to ensure files are not newer than coverage
    future_timestamp = Time.now.to_i + 3600
    bar_path = File.join(root, 'lib', 'bar.rb')
    foo_path = File.join(root, 'lib', 'foo.rb')

    mock_resultset_with_timestamp(root, future_timestamp, coverage: {
      bar_path => { 'lines' => [nil, nil, 1, 0, 1] }, # 5 lines matching bar.rb
      foo_path => { 'lines' => [nil, nil, 1, 0, nil, 2] }, # 6 lines matching foo.rb
    })

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    # Should not raise - all files are current
    expect { model.list(raise_on_stale: true) }.not_to raise_error
  end

  it 'raises when a file in coverage no longer exists' do
    # Create coverage for a non-existent file
    missing_path = File.join(root, 'lib', 'deleted_file.rb')

    mock_resultset_with_timestamp(root, Time.now.to_i, coverage: {
      missing_path => { 'lines' => [1, 1, 1] },
    })

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
      expect(error.deleted_files).to include('lib/deleted_file.rb')
    end
  end

  it 'prioritizes length-based staleness over time-based for the same file' do
    # Create coverage with old timestamp AND different line count
    old_timestamp = Time.now.to_i - 3600
    bar_path = File.join(root, 'lib', 'bar.rb')
    current_time = Time.now

    mock_resultset_with_timestamp(root, old_timestamp, coverage: {
      bar_path => { 'lines' => [1, 1] }, # 2 lines vs 5 in actual file
    })

    # Stub mtime to simulate file being newer than coverage
    allow(File).to receive(:mtime).and_wrap_original do |m, path|
      path.to_s == bar_path ? current_time : m.call(path)
    end

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
      # File should be in length_mismatch_files
      expect(error.length_mismatch_files).to include('lib/bar.rb')
      # But NOT in newer_files (length mismatch takes precedence)
      expect(error.newer_files).not_to include('lib/bar.rb')
    end
  end

  it 'includes length_mismatch_files in error message' do
    bar_path = File.join(root, 'lib', 'bar.rb')

    mock_resultset_with_timestamp(root, Time.now.to_i, coverage: {
      bar_path => { 'lines' => [1, 1] }, # 2 lines vs 3 in actual file
    })

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
      error_message = error.user_friendly_message
      expect(error_message).to include('Line count mismatch')
      expect(error_message).to include('lib/bar.rb')
    end
  end

  it 'detects multiple staleness types in one project' do
    old_timestamp = Time.now.to_i - 3600
    bar_path = File.join(root, 'lib', 'bar.rb')
    foo_path = File.join(root, 'lib', 'foo.rb')
    missing_path = File.join(root, 'lib', 'deleted.rb')
    current_time = Time.now

    mock_resultset_with_timestamp(root, old_timestamp, coverage: {
      bar_path     => { 'lines' => [nil, nil, 1, 0, 1] }, # 5 lines matching bar.rb - will be newer (T)
      foo_path     => { 'lines' => [1, 1] },              # 2 lines vs 6 actual - length mismatch (L)
      missing_path => { 'lines' => [1, 1, 1] },        # doesn't exist - missing (M)
    })

    # Stub mtime to make it newer than coverage
    allow(File).to receive(:mtime).and_wrap_original do |m, path|
      path.to_s == bar_path ? current_time : m.call(path)
    end

    model = described_class.new(root: root, coverage_file: FIXTURE_PROJECT1_RESULTSET_PATH,
      raise_on_stale: true)

    expect do
      model.list(raise_on_stale: true)
    end.to raise_error(CovLoupe::CoverageDataProjectStaleError) do |error|
      # Verify all three staleness types detected
      expect(error.newer_files).to include('lib/bar.rb')
      expect(error.length_mismatch_files).to include('lib/foo.rb')
      expect(error.deleted_files).to include('lib/deleted.rb')

      # Verify error message mentions all types
      message = error.user_friendly_message
      expect(message).to match(/newer.*bar\.rb/im)
      expect(message).to match(/line count mismatch.*foo\.rb/im)
      expect(message).to match(/deleted.*deleted\.rb/im)
    end
  end
end
