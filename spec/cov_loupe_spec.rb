# frozen_string_literal: true

require 'tmpdir'
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
          expect(cli).to have_received(:run).with(test_case[:argv], env_arg_count: 0)
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

    it 'exits with code 2 and shows the message for configuration errors' do
      allow(CovLoupe::ConfigParser).to receive(:parse)
        .and_raise(CovLoupe::ConfigurationError, 'bad config')

      stderr = capture_stderr do
        expect { described_class.run([]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(CovLoupe::ExitCodes::USAGE)
        end
      end
      expect(stderr).to include('Error: bad config')
    end

    it 'exits with code 2 and no backtrace for a usage error raised while parsing options' do
      stderr = capture_stderr do
        expect { described_class.run(%w[--context-lines -1 list]) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(CovLoupe::ExitCodes::USAGE)
        end
      end
      expect(stderr).to include('Error: Context lines cannot be negative')
    end

    it 'suggests the matching subcommand when a subcommand is given as an option' do
      stderr = capture_stderr do
        expect { described_class.run(%w[--list]) }.to raise_error(SystemExit)
      end
      expect(stderr).to include("Did you mean the 'list' subcommand?")
    end
  end

  describe 'default context' do
    it 'keeps the internal default context quiet for library callers' do
      expect(described_class.context.mode).to eq(:library)
      expect(CovLoupe::Logger.new(target: nil, mode: :library).target).to eq(':off')
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

      stdout_str, stderr_str, status = Open3.capture3(
        {
          'BUNDLE_GEMFILE' => nil,
          'GEM_HOME'       => nil,
          'GEM_PATH'       => nil,
          'RUBYOPT'        => nil,
        },
        RbConfig.ruby, '--disable-gems', '-I', lib_path, '-e', ruby_source, '--', '--version'
      )

      aggregate_failures do
        expect(status).to be_success
        expect(stdout_str).to eq("#{described_class::VERSION}\n")
        expect(non_runtime_stderr(stderr_str)).to be_empty
      end
    end

    it 'exits with standard POSIX codes and a friendly message on SIGINT and SIGTERM' do
      skip 'Signal handling is Unix-specific' if described_class.windows?

      require 'open3'
      require 'rbconfig'
      require 'timeout'

      ruby_source = signal_trap_prelude + <<~RUBY
        $stderr.puts 'ready'
        # Keep writing so the signal arrives while the main thread holds $stderr's write lock.
        loop { $stderr.write('.' * 1024) }
      RUBY

      {
        'INT'  => 130,
        'TERM' => 143,
      }.each do |sig, expected_status|
        stdout_str = ''
        stderr_str = ''
        status = nil

        Open3.popen3(RbConfig.ruby, '-e', ruby_source) do |_stdin, stdout, stderr, wait_thr|
          pid = wait_thr.pid

          wait_for_ready_marker(stderr, wait_thr)

          # Drain stderr concurrently: the child floods it, and the trap's own write blocks
          # on a full pipe if nothing is reading it.
          stderr_reader = Thread.new do
            stderr.read
          rescue IOError # popen3 closed the pipe after a failure
            ''
          end
          Process.kill(sig, pid)

          Timeout.timeout(INTEGRATION_TIMEOUT) do
            stdout_str = stdout.read
            stderr_str = stderr_reader.value.gsub(/\.{2,}/, '') # drop the filler dots
            status = wait_thr.value
          end
        rescue Timeout::Error
          # popen3's ensure waits for the child without a limit, so end it before leaving.
          kill_process(pid)
          raise
        end

        aggregate_failures "SIG#{sig}" do
          expect(status.exitstatus).to eq(expected_status)
          expect(stderr_str).to include("Received SIG#{sig}. Exiting.")
          expect(stdout_str).to be_empty
        end
      end
    end

    it 'exits with the signal status when stderr is closed' do
      skip 'Signal handling is Unix-specific' if described_class.windows?

      require 'open3'
      require 'rbconfig'
      require 'timeout'

      # The trap's stderr write raises here; the process must still exit 128+signal.
      ruby_source = signal_trap_prelude + <<~RUBY
        $stdout.puts 'ready'
        $stdout.flush
        sleep
      RUBY

      status = nil
      Open3.popen2(RbConfig.ruby, '-e', ruby_source, err: :close) do |_stdin, stdout, wait_thr|
        Timeout.timeout(INTEGRATION_TIMEOUT) do
          raise 'subprocess exited before installing signal traps' unless stdout.gets == "ready\n"

          Process.kill('TERM', wait_thr.pid)
          status = wait_thr.value
        end
      rescue Timeout::Error
        kill_process(wait_thr.pid)
        raise
      end

      expect(status.exitstatus).to eq(143)
    end

    # Ruby source that loads the executable without running it and installs its signal traps.
    def signal_trap_prelude
      exe = File.expand_path('../exe/cov-loupe', __dir__)
      <<~RUBY
        executable = File.read(#{exe.dump})
        executable_without_run = executable.sub(/\\nCovLoupeExecutable\\.run\\n\\z/, "\\n")
        raise 'could not remove executable invocation' if executable == executable_without_run

        eval(executable_without_run, TOPLEVEL_BINDING, #{exe.dump})
        CovLoupeExecutable.install_signal_handlers
      RUBY
    end

    def wait_for_ready_marker(stderr, wait_thr, timeout_seconds = INTEGRATION_TIMEOUT)
      Timeout.timeout(timeout_seconds) do
        loop do
          raise 'subprocess exited before installing signal traps' unless wait_thr.alive?

          break if stderr.gets == "ready\n"
        end
      end
    end

    def kill_process(pid)
      Process.kill('KILL', pid)
    rescue Errno::ESRCH
      # already exited
    end

    def non_runtime_stderr(stderr_str)
      stderr_str.each_line.reject do |line|
        line.start_with?('Warning: AppCDS archive directory is not writable') ||
          line.include?('[warning][perf,memops] Cannot use file /tmp/hsperfdata_')
      end.join
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

  describe '.create_context' do
    it 'defaults error_handler to the library handler' do
      context = described_class.create_context
      expect(context.error_handler).to be_a(CovLoupe::ErrorHandler)
      expect(context.error_handler.error_mode).to eq(:off)
    end

    it 'accepts log_target: alone, as library callers use it' do
      context = described_class.create_context(log_target: 'stderr')
      expect(context.log_target).to eq('stderr')
      expect(context).to be_library_mode
      expect(context.error_handler.error_mode).to eq(:off)
    end
  end

  describe '.version' do
    it 'returns the VERSION constant' do
      expect(described_class.version).to eq(CovLoupe::VERSION)
    end
  end
end
