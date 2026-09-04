# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Deprecation do
  around do |example|
    described_class.reset!
    described_class.enabled = true
    example.run
    described_class.reset!
    described_class.enabled = false
  end

  describe '.warn' do
    it 'names the old spelling, the replacement, and the removal version' do
      expected = Regexp.new(
        '--resultset is deprecated and will be removed in ' \
        "v#{Regexp.escape(described_class::REMOVAL_VERSION)}; use --coverage-file instead"
      )

      expect { described_class.warn('--resultset', '--coverage-file') }
        .to output(expected).to_stderr
    end

    it 'warns only once for the same pair' do
      expect do
        3.times { described_class.warn('--resultset', '--coverage-file') }
      end.to output(/\A[^\n]+\n\z/).to_stderr
    end

    it 'warns separately for different pairs' do
      expect do
        described_class.warn('--resultset', '--coverage-file')
        described_class.warn('#resultset_path', '#coverage_file_path')
      end.to output(/--resultset.*\n.*#resultset_path/m).to_stderr
    end

    it 'logs the warning' do
      logger = instance_double('CovLoupe::Logger', safe_log: nil)
      allow(CovLoupe).to receive(:logger).and_return(logger)

      suppress_io { described_class.warn('--resultset', '--coverage-file') }

      expect(logger).to have_received(:safe_log).with(/--resultset is deprecated/)
    end

    it 'stays silent when disabled' do
      described_class.enabled = false

      expect { described_class.warn('--resultset', '--coverage-file') }.not_to output.to_stderr
    end

    it 'keeps stderr clean in MCP mode, where stderr is server noise' do
      context = CovLoupe.create_context(error_handler: CovLoupe::ErrorHandler.new, mode: :mcp)

      expect do
        CovLoupe.with_context(context) { described_class.warn('--resultset', '--coverage-file') }
      end.not_to output.to_stderr
    end

    it 'never raises, so a deprecated call still completes' do
      allow(CovLoupe).to receive(:logger).and_raise(RuntimeError, 'logger exploded')

      expect { described_class.warn('--resultset', '--coverage-file') }.not_to raise_error
    end
  end
end
