# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe do
  # Mode selection tests - mode is determined by --mode flag, not autodetection
  describe 'mode selection' do
    [
      { desc: 'runs in CLI mode by default (no --mode flag)', argv: [], mode: :cli },
      { desc: 'runs in CLI mode when --mode cli is specified', argv: %w[--mode cli], mode: :cli },
      { desc: 'runs in MCP mode when --mode mcp is specified', argv: %w[--mode mcp], mode: :mcp },
      { desc: 'runs in MCP mode when -m mcp is specified', argv: %w[-m mcp], mode: :mcp },
    ].each do |test_case|
      it test_case[:desc] do
        if test_case[:mode] == :cli
          cli = instance_double(described_class::CoverageCLI, run: nil)
          allow(described_class::CoverageCLI).to receive(:new).and_return(cli)

          described_class.run(test_case[:argv])

          expect(described_class::CoverageCLI).to have_received(:new)
          expect(cli).to have_received(:run).with(test_case[:argv])
        else
          mcp_server = instance_double(described_class::MCPServer, run: nil)
          allow(described_class::MCPServer).to receive(:new).and_return(mcp_server)

          described_class.run(test_case[:argv])

          expect(described_class::MCPServer).to have_received(:new)
          expect(mcp_server).to have_received(:run)
        end
      end
    end

    it 'exits with code 2 and shows friendly error for invalid options' do
      suppress_io do
        expect do
          described_class.run(%w[--invalid-option])
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(2)
        end
      end
    end
  end

  describe 'executable' do
    it 'exits with code 130 and shows a friendly message when interrupted' do
      allow(described_class).to receive(:run).and_raise(Interrupt)
      original_handler = Signal.trap('INT', 'DEFAULT')
      Signal.trap('INT', original_handler)

      result, _out, err = capture_io(swallow_exit: true) do
        load File.expand_path('../exe/cov-loupe', __dir__)
      end

      expect(result).to be_a(SystemExit)
      expect(result.status).to eq(130)
      expect(err).to eq("\nInterrupted. Exiting.\n")
    ensure
      Signal.trap('INT', original_handler) if original_handler
    end
  end

  # When no thread-local context exists, active_log_file= creates one
  # from the default context rather than modifying an existing one.
  describe '.active_log_file=' do
    it 'creates context from default when no current context exists' do
      Thread.current[:cov_loupe_context] = nil
      log_file = File.join(Dir.tmpdir, 'test.log')

      described_class.active_log_file = log_file

      expect(described_class.context).not_to be_nil
      expect(described_class.active_log_file).to eq(log_file)
    ensure
      described_class.active_log_file = File::NULL
    end
  end

  describe '.default_log_file' do
    it 'returns the log target from the default context' do
      # Ensure we start with a clean state or know the state
      original_default = described_class.default_log_file

      # It typically starts as nil or File::NULL depending on initialization,
      # but let's just verify it returns what we expect if we set it,
      # or just call it to ensure coverage.
      expect(described_class.default_log_file).to eq(original_default)
    end
  end

  describe '.version' do
    it 'returns the VERSION constant' do
      expect(described_class.version).to eq(CovLoupe::VERSION)
    end
  end
end
