# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::AppConfig do
  describe '#initialize' do
    it 'creates a config with default values' do
      config = described_class.new
      expect(config.root).to eq('.')
      expect(config.format).to eq(:table)
      expect(config.sort_order).to eq(:descending)
      expect(config.source_context).to eq(2)
      expect(config.error_mode).to eq(:log)
      expect(config.raise_on_stale).to be(false)
      expect(config.coverage_file).to be_nil
      expect(config.source_mode).to be_nil
      expect(config.tracked_globs).to eq([])
      expect(config.log_file).to be_nil
    end

    it 'applies default tracked globs when not provided' do
      config = described_class.new
      expect(config.tracked_globs).to eq([])
    end

    it 'allows explicitly setting tracked_globs to empty array' do
      config = described_class.new(tracked_globs: [])
      expect(config.tracked_globs).to eq([])
    end

    it 'allows overriding default tracked_globs with custom values' do
      config = described_class.new(tracked_globs: ['custom/**/*.rb'])
      expect(config.tracked_globs).to eq(['custom/**/*.rb'])
    end

    it 'allows overriding defaults via keyword arguments' do
      config = described_class.new(
        root:           '/custom',
        format:         :json,
        sort_order:     :descending,
        raise_on_stale: true
      )
      expect(config.root).to eq('/custom')
      expect(config.format).to eq(:json)
      expect(config.sort_order).to eq(:descending)
      expect(config.raise_on_stale).to be(true)
    end

    it 'is mutable (struct fields can be changed)' do
      config = described_class.new
      config.root = '/new/root'
      config.format = :json
      expect(config.root).to eq('/new/root')
      expect(config.format).to eq(:json)
    end
  end

  describe '#model_options' do
    it 'returns hash suitable for CoverageModel.new' do
      config = described_class.new(
        root:           '/custom/root',
        coverage_file:  '/custom/coverage.json',
        raise_on_stale: true,
        tracked_globs:  ['lib/**/*.rb']
      )

      options = config.model_options
      expect(options).to eq({
        root:           '/custom/root',
        coverage_file:  '/custom/coverage.json',
        raise_on_stale: true,
        tracked_globs:  ['lib/**/*.rb'],
      })
    end

    it 'handles default values correctly' do
      config = described_class.new
      options = config.model_options
      expect(options[:root]).to eq('.')
      expect(options[:coverage_file]).to be_nil
      expect(options[:raise_on_stale]).to be(false)
      expect(options[:tracked_globs]).to eq([])
    end
  end

  describe '#formatter_options' do
    it 'returns hash suitable for SourceFormatter.new' do
      config = described_class.new(color: true)
      options = config.formatter_options
      expect(options).to eq({ color_enabled: true, output_chars: :default })
    end

    it 'handles false color setting' do
      config = described_class.new(color: false)
      options = config.formatter_options
      expect(options).to eq({ color_enabled: false, output_chars: :default })
    end
  end

  describe 'struct behavior' do
    it 'supports equality comparison' do
      config1 = described_class.new(root: '/foo', format: :json)
      config2 = described_class.new(root: '/foo', format: :json)
      config3 = described_class.new(root: '/bar', format: :json)

      expect(config1).to eq(config2)
      expect(config1).not_to eq(config3)
    end

    it 'provides readable inspect output' do
      config = described_class.new(root: '/test', format: :json)
      output = config.inspect
      expect(output).to include('root="/test"')
      expect(output).to include('format=:json')
    end

    it 'converts to hash' do
      config = described_class.new(root: '/test', format: :json)
      hash = config.to_h
      expect(hash).to be_a(Hash)
      expect(hash[:root]).to eq('/test')
      expect(hash[:format]).to eq(:json)
    end
  end

  describe '#validate!' do
    it 'accepts nil log_file' do
      config = described_class.new
      expect { config.validate! }.not_to raise_error
    end

    it 'accepts a file path log_file' do
      config = described_class.new(log_file: '/tmp/cov-loupe.log')
      expect { config.validate! }.not_to raise_error
    end

    it 'accepts stderr log_file' do
      config = described_class.new(log_file: 'stderr')
      expect { config.validate! }.not_to raise_error
    end

    it 'accepts :off log_file' do
      config = described_class.new(log_file: ':off')
      expect { config.validate! }.not_to raise_error
    end

    it 'rejects stdout log_file' do
      config = described_class.new(log_file: 'stdout')
      expect do
        config.validate!
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'rejects stdout with surrounding whitespace' do
      config = described_class.new(log_file: '  stdout  ')
      expect do
        config.validate!
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'rejects uppercase stdout' do
      config = described_class.new(log_file: 'STDOUT')
      expect do
        config.validate!
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end
  end

  describe 'symbol enumerated values' do
    it 'uses symbols for format' do
      config = described_class.new(format: :json)
      expect(config.format).to eq(:json)
      expect(config.format).to be_a(Symbol)
    end

    it 'uses symbols for sort_order' do
      config = described_class.new(sort_order: :descending)
      expect(config.sort_order).to eq(:descending)
      expect(config.sort_order).to be_a(Symbol)
    end

    it 'uses symbols for error_mode' do
      config = described_class.new(error_mode: :debug)
      expect(config.error_mode).to eq(:debug)
      expect(config.error_mode).to be_a(Symbol)
    end

    it 'uses symbols for source_mode' do
      config = described_class.new(source_mode: :uncovered)
      expect(config.source_mode).to eq(:uncovered)
      expect(config.source_mode).to be_a(Symbol)
    end
  end
end
