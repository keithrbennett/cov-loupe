# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/model/model_data_cache'
require 'cov_loupe/model/model_data'

RSpec.describe CovLoupe::ModelDataCache do
  let(:cache) { described_class.instance }
  let(:project1_root) { (FIXTURES_DIR / 'project1').to_s }
  let(:project1_resultset) { FIXTURE_PROJECT1_RESULTSET_PATH }

  # Clear the singleton cache before each test
  before { cache.clear }

  describe '#get' do
    it 'returns ModelData with coverage data' do
      data = cache.get(project1_resultset, root: project1_root)
      expect(data).to be_a(CovLoupe::ModelData)
      expect(data.coverage_map).to be_a(Hash)
      expect(data.timestamp).to be_a(Integer)
      expect(data.coverage_file_path).to eq(project1_resultset)
    end

    it 'returns the same data for identical resultset path and root' do
      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      expect(data1).to eq(data2)
    end

    it 'creates separate cache entries for different roots with same resultset' do
      Dir.mktmpdir('cache_test') do |temp_dir|
        data1 = cache.get(project1_resultset, root: project1_root)
        data2 = cache.get(project1_resultset, root: temp_dir)
        # Should create separate cache entries because path normalization depends on root
        expect(data2).not_to be(data1)
        # But both should contain valid coverage data from the same resultset
        expect(data1.coverage_file_path).to eq(data2.coverage_file_path)
        expect(data1.timestamp).to eq(data2.timestamp)
      end
    end

    it 'reloads data when resultset mtime changes' do
      stat_now = double('File::Stat', mtime: Time.at(100), size: 10, ino: 1)
      stat_later = double('File::Stat', mtime: Time.at(200), size: 10, ino: 1)

      mock_file_stat(project1_resultset, mtime: Time.at(100), sequence: [stat_now, stat_later])

      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      # Should reload and get new data (different object)
      expect(data2).not_to be(data1)
    end

    it 'detects subsecond mtime changes' do
      base_time = Time.at(100)
      stat_now = double('File::Stat', mtime: base_time, size: 10, ino: 1)
      allow(stat_now).to receive(:mtime_nsec).and_return(0)

      stat_subsecond = double('File::Stat', mtime: base_time, size: 10, ino: 1)
      allow(stat_subsecond).to receive(:mtime_nsec).and_return(1_000_000)

      mock_file_stat(project1_resultset, mtime: base_time, sequence: [stat_now, stat_subsecond])

      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      expect(data2).not_to be(data1)
    end

    it 'reloads when size changes within the same second' do
      base_time = Time.at(100)
      stat_now = double('File::Stat', mtime: base_time, size: 10, ino: 1)
      allow(stat_now).to receive(:mtime_nsec).and_return(0)

      stat_size_change = double('File::Stat', mtime: base_time, size: 11, ino: 1)
      allow(stat_size_change).to receive(:mtime_nsec).and_return(0)

      mock_file_stat(project1_resultset, mtime: base_time, sequence: [stat_now, stat_size_change])

      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      expect(data2).not_to be(data1)
    end

    it 'reloads when content changes but metadata is identical' do
      mock_file_stat(project1_resultset, mtime: Time.at(100), mtime_nsec: 0, size: 10, ino: 1)
      mock_file_digest(project1_resultset, sequence: %w[digest_v1 digest_v2])

      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      expect(data2).not_to be(data1)
    end

    it 'validates digest on every get call' do
      mock_file_stat(project1_resultset, mtime: Time.at(100), mtime_nsec: 0, size: 10, ino: 1)
      mock_file_digest(project1_resultset, digest: 'unchanged', sequence: %w[unchanged unchanged])

      data1 = cache.get(project1_resultset, root: project1_root)
      data2 = cache.get(project1_resultset, root: project1_root)
      expect(data2).to eq(data1)
    end

    it 'handles stat computation failures gracefully' do
      allow(File).to receive(:stat).with(project1_resultset).and_raise(Errno::ENOENT)

      # Should load data but not cache it
      expect { cache.get(project1_resultset, root: project1_root) }.not_to raise_error
    end

    it 'handles digest computation failures gracefully' do
      mock_file_stat(project1_resultset, mtime: Time.at(100), mtime_nsec: 0, size: 10, ino: 1)
      allow(Digest::MD5).to receive(:file).with(project1_resultset).and_raise(Errno::EACCES)

      # Should load data but not cache it
      expect { cache.get(project1_resultset, root: project1_root) }.not_to raise_error
    end
  end

  describe '#clear' do
    it 'clears all cached entries' do
      mock_file_stat(project1_resultset, mtime: Time.at(100), mtime_nsec: 0, size: 10, ino: 1)
      mock_file_digest(project1_resultset, digest: 'unchanged', sequence: %w[unchanged unchanged])

      data1 = cache.get(project1_resultset, root: project1_root)
      cache.clear
      data2 = cache.get(project1_resultset, root: project1_root)

      # After clear, should reload (different object)
      expect(data2).not_to be(data1)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access safely' do
      threads = 10.times.map do
        Thread.new do
          data = cache.get(project1_resultset, root: project1_root)
          expect(data).to be_a(CovLoupe::ModelData)
        end
      end
      threads.each(&:join)
    end

    it 'ensures singleton instance creation is thread-safe' do
      # Reset the singleton to test concurrent initialization
      # Note: INSTANCE_MUTEX constant cannot and should not be reset
      described_class.instance_variable_set(:@instance, nil)

      instances = []
      mutex = Mutex.new

      threads = 10.times.map do
        Thread.new do
          instance = described_class.instance
          mutex.synchronize { instances << instance }
        end
      end
      threads.each(&:join)

      # All threads should get the exact same instance object
      expect(instances.uniq.size).to eq(1)
    end
  end

  describe 'per-model logger support' do
    it 'uses the provided logger when loading fresh data' do
      custom_logger = double('Logger')

      # Verify logger is passed through to CoverageRepository
      expect(CovLoupe::Repositories::CoverageRepository).to receive(:new)
        .with(hash_including(logger: custom_logger))
        .and_call_original

      data = cache.get(project1_resultset, root: project1_root, logger: custom_logger)
      expect(data).to be_a(CovLoupe::ModelData)
    end

    it 'falls back to CovLoupe.logger when no logger is provided' do
      # Verify logger fallback to CovLoupe.logger
      expect(CovLoupe::Repositories::CoverageRepository).to receive(:new)
        .with(hash_including(logger: CovLoupe.logger))
        .and_call_original

      data = cache.get(project1_resultset, root: project1_root)
      expect(data).to be_a(CovLoupe::ModelData)
    end
  end
end
