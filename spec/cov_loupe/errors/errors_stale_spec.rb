# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageDataStaleError do
  it 'formats a detailed, user-friendly message with UTC/local, delta, and resultset' do
    file_time = Time.at(TEST_FILE_TIMESTAMP) # 1970-01-01T00:16:40Z
    cov_epoch = VERY_OLD_TIMESTAMP           # 1970-01-01T00:00:00Z
    err = described_class.new(
      'Coverage data appears stale for foo.rb',
      nil,
      file_path:          'foo.rb',
      file_mtime:         file_time,
      cov_timestamp:      cov_epoch,
      src_len:            10,
      cov_len:            8,
      coverage_file_path: '/path/to/coverage/.resultset.json'
    )

    msg = err.user_friendly_message

    expect(msg).to include('Coverage data stale: Coverage data appears stale for foo.rb')
    expect(msg).to match(/File\s*-\s*time:\s*1970-01-01T00:16:40Z/)
    expect(msg).to include('(local ') # do not assert exact local tz
    expect(msg).to match(/Coverage\s*-\s*time:\s*1970-01-01T00:00:01Z/)
    expect(msg).to match(/lines:\s*10/)
    expect(msg).to match(/lines:\s*8/)
    expect(msg).to match(/Delta\s*- file is \+999s newer than coverage/)
    expect(msg).to include('Resultset - /path/to/coverage/.resultset.json')
  end

  it 'handles missing timestamps gracefully' do
    err = described_class.new(
      'Coverage data appears stale for bar.rb',
      nil,
      file_path:          'bar.rb',
      file_mtime:         nil,
      cov_timestamp:      nil,
      src_len:            1,
      cov_len:            0,
      coverage_file_path: nil
    )
    msg = err.user_friendly_message
    expect(msg).to include('Coverage data stale: Coverage data appears stale for bar.rb')
    expect(msg).to match(/File\s*-\s*time:\s*not found.*lines: 1/m)
    expect(msg).to match(/Coverage\s*-\s*time:\s*not found.*lines: 0/m)
    expect(msg).not_to include('Delta')
  end

  it 'uses default message when message is nil' do
    err = described_class.new(
      nil,
      nil,
      file_path:          'lib/example.rb',
      file_mtime:         Time.now,
      cov_timestamp:      Time.now.to_i - 1000,
      src_len:            10,
      cov_len:            8,
      coverage_file_path: '/coverage/.resultset.json'
    )

    msg = err.user_friendly_message
    expect(msg).to include('Coverage data stale:')
    expect(msg).to include('Coverage data appears stale for lib/example.rb')
  end

  it 'uses "file" in default message when file_path is also nil' do
    err = described_class.new(
      nil,
      nil,
      file_path:          nil,
      file_mtime:         nil,
      cov_timestamp:      nil,
      src_len:            0,
      cov_len:            0,
      coverage_file_path: nil
    )

    msg = err.user_friendly_message
    expect(msg).to include('Coverage data stale:')
    expect(msg).to include('Coverage data appears stale for file')
  end

  context 'when checking staleness with permission errors' do
    require 'tmpdir'
    require 'fileutils'

    let(:tmpdir) { Dir.mktmpdir('scmcp-perms') }
    let(:file) { File.join(tmpdir, 'lib', 'test.rb') }
    let(:checker) do
      CovLoupe::StalenessChecker.new(
        root:          tmpdir,
        coverage_file: nil,
        mode:          :error,
        timestamp:     Time.now
      )
    end

    after { FileUtils.remove_entry(tmpdir) if tmpdir && File.directory?(tmpdir) }

    shared_examples 'raises FileError with descriptive message' do
      it 'raises FileError instead of CoverageDataStaleError' do
        expect { checker.check_file!(file, coverage_lines) }
          .to raise_error(CovLoupe::FileError) do |error|
            expect(error.message).to include('Error reading file')
            expect(error.message).to include('lib/test.rb')
          end
      end
    end

    context 'when file is unreadable during line counting' do
      let(:coverage_lines) { [1, 1, 1] }

      before do
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "line1\nline2\nline3\n")
        # Mock File.read to simulate permission denied
        allow(File).to receive(:read).with(file)
          .and_raise(Errno::EACCES.new('Permission denied'))
      end

      it_behaves_like 'raises FileError with descriptive message'
    end
  end
end
