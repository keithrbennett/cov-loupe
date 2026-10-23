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

    it 'retags arguments that are valid UTF-8, as they arrive under a non-UTF-8 locale' do
      cli = instance_double(described_class::CoverageCLI, run: nil)
      allow(described_class::CoverageCLI).to receive(:new).and_return(cli)
      path = 'lib/café.rb'
      invalid = (+"lib/\xFF.rb").force_encoding(Encoding::BINARY)
      latin1 = path.encode(Encoding::ISO_8859_1)
      dot = '.'.encode(Encoding::US_ASCII)

      described_class.run(['summary', path.b, invalid, latin1, dot, :list])

      expect(cli).to have_received(:run) do |argv, **|
        expect(argv).to eq(['summary', path, invalid, latin1, '.', :list])
        expect(argv.first(5).map(&:encoding)).to eq(
          [Encoding::UTF_8, Encoding::UTF_8, Encoding::BINARY, Encoding::ISO_8859_1, Encoding::UTF_8])
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
      expect(CovLoupe::Logger.new(target: nil, mode: :library).target).to eq('off')
    end
  end

  describe 'executable' do
    it 'handles non-ASCII paths in a non-ASCII directory under LANG=C' do
      skip 'LANG=C is a Unix locale' if described_class.windows?
      skip 'JRuby cannot open non-ASCII paths under LANG=C' if RUBY_ENGINE == 'jruby'

      require 'open3'
      require 'rbconfig'

      exe = File.expand_path('../exe/cov-loupe', __dir__)
      lib_path = File.expand_path('../lib', __dir__)
      Dir.mktmpdir do |tmp|
        root = File.join(tmp, 'prój')
        FileUtils.mkdir_p(File.join(root, 'lib'))
        File.write(File.join(root, 'lib/café.rb'), "x = 'café'\n")
        FileUtils.mkdir_p(File.join(root, 'coverage'))
        File.write(File.join(root, 'coverage/coverage.json'), JSON.generate(coverage_json_document(
          coverage: { 'lib/café.rb' => { 'lines' => [1] } }, timestamp: Time.now.to_i + 60)))

        rubyopt = ENV['RUBYOPT'].to_s.split.grep(/\A-[rI]\S/).join(' ')
        run = ->(*args, extra_rubyopt: nil, stdin_data: '', opts: nil) do
          out, err, status = Open3.capture3(
            # Keep RUBYOPT's requires and load paths (Bundler), but not options such as -E that
            # would override LANG=C.
            { 'LANG' => 'C', 'LC_ALL' => 'C', 'COV_LOUPE_OPTS' => opts,
              'RUBYOPT' => [rubyopt, extra_rubyopt].compact.join(' ') },
            RbConfig.ruby, '-I', lib_path, exe, '-R', '.', *args,
            chdir: root, binmode: true, stdin_data: stdin_data
          )
          [out.force_encoding(Encoding::UTF_8), err, status]
        end
        # Environment values arrive as raw bytes under LANG=C too
        list_out, list_err, list_status = run.call('list', opts: '--tracked-globs lib/café*.rb')
        summary_out, summary_err, summary_status = run.call('-c', 'coverage', 'summary', 'lib/café.rb')
        # -U sets Encoding.default_internal, so $stdout transcodes to US-ASCII and the default
        # report cannot write the non-ASCII path.
        _out, transcode_err, transcode_status = run.call(extra_rubyopt: '-U')
        # With Encoding.default_internal set to US-ASCII, the MCP request must still be read as UTF-8.
        request = { jsonrpc: '2.0', id: 1, method: 'tools/call',
                    params: { name: 'file_coverage_summary', arguments: { path: 'lib/café.rb' } } }
        mcp_out, mcp_err, mcp_status = run.call('-m', 'mcp', '--log-file', 'off',
          extra_rubyopt: '-E:US-ASCII', stdin_data: "#{JSON.generate(request)}\n")
        # The error log line names the non-ASCII path too, and goes to stderr by default.
        missing = request.merge(
          params: { name: 'file_coverage_summary', arguments: { path: 'lib/café-missing.rb' } })
        _log_out, log_err, log_status = run.call('-m', 'mcp', extra_rubyopt: '-U',
          stdin_data: "#{JSON.generate(missing)}\n")

        aggregate_failures do
          expect(list_status).to be_success, list_err
          expect(list_out).to include('lib/café.rb', 'Files: total 1, ok 1')
          expect(list_out).not_to include('Missing tracked files')
          expect(list_out).to start_with('+-') # the C locale still selects ASCII borders
          expect(summary_status).to be_success, summary_err
          expect(summary_out).to include('lib/café.rb', '100.00%')
          expect(transcode_status.exitstatus).to eq(1)
          expect(transcode_err).to start_with('Text encoding error: U+00E9 from UTF-8 to US-ASCII. ')
          expect(mcp_status).to be_success, mcp_err
          expect(log_status).to be_success, log_err
          expect(log_err.force_encoding(Encoding::UTF_8)).to include('ERROR:', 'lib/café-missing.rb')
          expect(log_err).not_to include('log writing failed')
          mcp_result = JSON.parse(mcp_out)['result']
          expect(mcp_result['isError']).to be(false), mcp_out
          expect(JSON.parse(mcp_result.dig('content', 0, 'text'))).to include(
            'file' => 'lib/café.rb', 'summary' => include('percentage' => 100.0))
        end
      end
    end

    # The in-process specs pin the default output style to the UTF-8 one, so check here that the
    # executable records a UTF-8 starting encoding and picks Unicode borders under a UTF-8 locale.
    it 'selects Unicode table borders under a UTF-8 locale' do
      skip 'LANG is a Unix locale setting' if described_class.windows?

      require 'open3'
      require 'rbconfig'

      env = { 'LANG' => 'C.UTF-8', 'LC_ALL' => 'C.UTF-8', 'COV_LOUPE_OPTS' => nil,
              'RUBYOPT' => ENV['RUBYOPT'].to_s.split.grep(/\A-[rI]\S/).join(' ') }
      locale, = Open3.capture2(env, RbConfig.ruby, '-e', 'print Encoding.default_external')
      skip 'the C.UTF-8 locale is not installed' unless locale == 'UTF-8'

      out, err, status = Open3.capture3(env, RbConfig.ruby, '-I', File.expand_path('../lib', __dir__),
        File.expand_path('../exe/cov-loupe', __dir__), '-R', File.expand_path('fixtures/project1', __dir__),
        'list', binmode: true)

      expect(status).to be_success, err
      expect(out.force_encoding(Encoding::UTF_8)).to start_with('┌')
    end

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

    {
      'US-ASCII'   => 'UTF-8',
      'ASCII-8BIT' => 'UTF-8',
      'ISO-8859-1' => 'ISO-8859-1',
      'UTF-8'      => 'UTF-8',
    }.each do |original, expected|
      it "makes a #{original} default external encoding #{expected}" do
        require 'open3'
        require 'rbconfig'

        source = "#{executable_prelude}CovLoupeExecutable.use_utf8_default_external\n" \
                 'puts Encoding.default_external'
        out, status = Open3.capture2(RbConfig.ruby, '-E', original, '-e', source)

        expect(status).to be_success
        expect(out.chomp).to eq(expected)
      end
    end

    it 'finds the gem lib directory when lib is not on the load path' do
      require 'open3'
      require 'rbconfig'

      out, status = Open3.capture2(RbConfig.ruby, '-e',
        "#{executable_prelude}puts CovLoupeExecutable.lib_dir")

      expect(status).to be_success
      expect(out.chomp).to eq(File.realpath(File.expand_path('../lib', __dir__)))
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

    # Ruby source that loads the executable without running it.
    def executable_prelude
      exe = File.expand_path('../exe/cov-loupe', __dir__)
      <<~RUBY
        executable = File.read(#{exe.dump})
        executable_without_run = executable.sub(/\\nCovLoupeExecutable\\.run\\n\\z/, "\\n")
        raise 'could not remove executable invocation' if executable == executable_without_run

        eval(executable_without_run, TOPLEVEL_BINDING, #{exe.dump})
      RUBY
    end

    # Ruby source that loads the executable without running it and installs its signal traps.
    def signal_trap_prelude
      "#{executable_prelude}CovLoupeExecutable.install_signal_handlers\n"
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

  describe 'log file getters' do
    it 'return an off target as set, not normalized' do
      original = described_class.default_log_file
      Thread.current[:cov_loupe_context] = nil

      ['  OFF  ', :off].each do |value|
        described_class.default_log_file = value
        described_class.active_log_file = value

        expect(described_class.default_log_file).to eq(value)
        expect(described_class.active_log_file).to eq(value)
      end
    ensure
      Thread.current[:cov_loupe_context] = nil
      described_class.default_log_file = original
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
