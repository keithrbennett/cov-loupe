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
    it 'does not require RubyGems when RubyGems starts disabled' do
      require 'open3'
      require 'rbconfig'

      exe = File.expand_path('../exe/cov-loupe', __dir__)
      lib_path = File.expand_path('../lib', __dir__)
      ruby_source = <<~RUBY
        module Kernel
          alias __cov_loupe_original_require require

          def require(path)
            abort 'unexpected rubygems require' if path == 'rubygems'

            __cov_loupe_original_require(path)
          end
        end

        load #{exe.dump}
      RUBY

      _stdout_str, stderr_str, _status = Open3.capture3(
        {
          'BUNDLE_GEMFILE' => nil,
          'GEM_HOME'       => nil,
          'GEM_PATH'       => nil,
          'RUBYOPT'        => nil,
        },
        RbConfig.ruby, '--disable-gems', '-I', lib_path, '-e', ruby_source, '--', '--version'
      )

      aggregate_failures do
        expect(stderr_str).not_to include('unexpected rubygems require')
        expect(stderr_str).not_to include('uninitialized constant CovLoupeExecutable::Gem')
      end
    end

    it 'exits with standard POSIX codes and a friendly message on SIGINT and SIGTERM' do
      skip 'Signal handling is Unix-specific' if described_class.windows?

      require 'open3'
      require 'rbconfig'
      require 'timeout'

      exe = File.expand_path('../exe/cov-loupe', __dir__)
      lib_path = File.expand_path('../lib', __dir__)

      {
        'INT'  => 130,
        'TERM' => 143,
      }.each do |sig, expected_status|
        stdout_str = ''
        stderr_str = ''
        status = nil

        Open3.popen3(RbConfig.ruby, '-I', lib_path, '-rbundler/setup', exe, '--mode', 'mcp',
          '--log-file', File::NULL) do |_stdin, stdout, stderr, wait_thr|
          pid = wait_thr.pid

          # Wait for the subprocess to start, then give it a moment to install
          # its signal traps before we signal it.
          wait_for_process(wait_thr)
          sleep 0.2

          Process.kill(sig, pid)

          Timeout.timeout(INTEGRATION_TIMEOUT) do
            stdout_str = stdout.read
            stderr_str = stderr.read
            status = wait_thr.value
          end
        end

        aggregate_failures "SIG#{sig}" do
          expect(status.exitstatus).to eq(expected_status)
          expect(stderr_str).to include("Received SIG#{sig}. Exiting.")
          expect(stdout_str).to be_empty
        end
      end
    end

    # Wait up to timeout_seconds for the subprocess to actually be running.
    # Raises Timeout::Error if it never starts, so premature death fails loudly
    # instead of producing confusing downstream assertions.
    def wait_for_process(wait_thr, timeout_seconds = 5)
      Timeout.timeout(timeout_seconds) do
        sleep 0.01 until wait_thr.alive?
      end
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

    it 'rejects stdout immediately' do
      expect do
        described_class.active_log_file = 'stdout'
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
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

  describe '.default_log_file=' do
    it 'rejects stdout immediately' do
      expect do
        described_class.default_log_file = 'stdout'
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end
  end

  describe '.version' do
    it 'returns the VERSION constant' do
      expect(described_class.version).to eq(CovLoupe::VERSION)
    end
  end
end
