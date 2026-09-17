# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Logging Fallback Behavior' do
  let(:fallback_file) { CovLoupe::Logger::FALLBACK_LOG_FILE }

  # Run all tests in a temporary directory to isolate fallback file creation
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        example.run
      end
    end
  end

  def with_stringio_logger(mode: :library)
    io = StringIO.new
    stdlib_logger = ::Logger.new(io)
    stdlib_logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.iso8601}] #{severity}: #{msg}\n"
    end
    logger = CovLoupe::Logger.new(target: 'stderr', mode: mode)
    logger.instance_variable_set(:@logger, stdlib_logger)
    yield logger, io
  end

  describe 'stdout logging prohibition' do
    it 'rejects stdout at Logger initialization' do
      expect do
        CovLoupe::Logger.new(target: 'stdout', mode: :library)
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'rejects stdout with surrounding whitespace' do
      expect do
        CovLoupe::Logger.new(target: '  stdout  ', mode: :cli)
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'rejects uppercase stdout' do
      expect do
        CovLoupe::Logger.new(target: 'STDOUT', mode: :mcp)
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'accepts stderr case-insensitively and with surrounding whitespace' do
      logger = CovLoupe::Logger.new(target: '  STDERR  ', mode: :library)
      io = StringIO.new
      stdlib_logger = ::Logger.new(io)
      logger.instance_variable_set(:@logger, stdlib_logger)

      logger.info('stderr message')

      expect(io.string).to include('stderr message')
      expect(File.exist?('  STDERR  ')).to be false
    end
  end

  describe 'CovLoupe.logger error handling' do
    it 'does not leave a persistent log file until the first message is logged' do
      logger = CovLoupe::Logger.new(target: nil, mode: :library)

      expect(logger.instance_variable_get(:@logger)).to be_nil
      expect(File.exist?('cov_loupe.log')).to be false

      logger.info('first message')

      expect(File.exist?('cov_loupe.log')).to be true
      expect(File.read('cov_loupe.log')).to include('first message')
    end

    it 'probes an existing log file in append mode without truncating it' do
      File.write('existing.log', "previous content\n")

      logger = CovLoupe::Logger.new(target: 'existing.log', mode: :library)

      expect(logger.instance_variable_get(:@init_error)).to be_nil
      expect(File.read('existing.log')).to eq("previous content\n")
    end

    it 'handles a race where another process creates the target during probing' do
      path = File.expand_path('race.log')
      open_flags = File::WRONLY | File::CREAT | File::EXCL
      allow(File).to receive(:exist?).with(path).and_return(false)
      allow(File).to receive(:open).with(path, open_flags, 0o644).and_raise(Errno::EEXIST)
      allow(File).to receive(:open).with(path, 'a').and_call_original

      logger = CovLoupe::Logger.new(target: 'race.log', mode: :library)

      expect(logger.instance_variable_get(:@init_error)).to be_nil
    end

    context 'when file logging fails in library mode' do
      it 'raises a logging configuration error during initialization' do
        expect do
          CovLoupe.create_context(
            error_handler: CovLoupe::ErrorHandlerFactory.for_library,
            log_target:    '/invalid/path/that/does/not/exist.log',
            mode:          :library
          )
        end.to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
      end
    end

    context 'when file logging fails in CLI mode' do
      it 'reports a probe failure immediately at initialization' do
        stderr_output = capture_stderr do
          CovLoupe::Logger.new(
            target: '/invalid/path/that/does/not/exist.log',
            mode:   :cli
          )
        end

        expect(stderr_output).to include('Warning: Configuration error: Unable to use log target')
        expect(File.exist?(fallback_file)).to be false
      end

      it 'writes to fallback file and prints each warning type exactly once' do
        stderr_output = nil
        capture_io do
          context = CovLoupe.create_context(
            error_handler: CovLoupe::ErrorHandlerFactory.for_cli,
            log_target:    '/invalid/path/that/does/not/exist.log',
            mode:          :cli
          )
          CovLoupe.with_context(context) do
            # First failure
            CovLoupe.logger.info('first failure')
            first_stderr = $stderr.string.dup
            $stderr.reopen(StringIO.new) # clear stderr buffer

            # Second failure
            CovLoupe.logger.info('second failure')
            second_stderr = $stderr.string

            stderr_output = first_stderr + second_stderr
          end
        end

        # Check stderr
        lines = stderr_output.split("\n")
        warning_msg = 'Warning: Configuration error: Unable to use log target'
        expect(lines.count { |l| l.include?(warning_msg) }).to eq(2)
        expect(lines.count { |l| l.include?('See COV-LOUPE-LOG-ERROR.log for details.') }).to eq(1)

        # Check fallback file
        expect(File.exist?(fallback_file)).to be true
        content = File.read(fallback_file)
        expect(content).to include('MODE:cli', 'MSG:first failure', 'MSG:second failure')
      end
    end

    context 'when file logging fails in MCP server mode' do
      it 'returns a tool error when the logging target is unavailable' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
          log_target:    '/invalid/path/that/does/not/exist.log',
          mode:          :mcp
        )

        response = CovLoupe.with_context(context) do
          CovLoupe::BaseTool.with_error_handling('test_tool', error_mode: :log) do
            raise 'business error'
          end
        end

        expect(response).to be_error
        expect(response.content.first['text']).to include('Unable to use log target')
      end

      it 'raises a logging configuration error when a write is attempted' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
          log_target:    '/invalid/path/that/does/not/exist.log',
          mode:          :mcp
        )

        expect do
          CovLoupe.with_context(context) do
            CovLoupe.logger.info('test message')
          end
        end.to raise_error(CovLoupe::LoggingError, /Unable to use log target/)

        expect(File.exist?(fallback_file)).to be true
        content = File.read(fallback_file)
        expect(content).to include('MODE:mcp', 'MSG:test message')
        expect(content.lines.count).to eq(1)
      end
    end

    context 'when logging succeeds' do
      it 'does not write to stderr or fallback file' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_library,
          log_target:    'stderr',
          mode:          :library
        )
        with_stringio_logger(mode: :library) do |logger, io|
          context = context.with(logger: logger)

          stderr_output = nil
          CovLoupe.with_context(context) do
            _result, _out, stderr_output = capture_io do
              CovLoupe.logger.info('test message')
            end
          end

          expect(stderr_output).to be_empty
          expect(File.exist?(fallback_file)).to be false
          expect(io.string).to include('test message')
        end
      end
    end
  end

  describe 'CovLoupe::Logger log levels' do
    [
      { level: :info, severity: 'INFO', message: 'info message' },
      { level: :warn, severity: 'WARN', message: 'warning message' },
      { level: :error, severity: 'ERROR', message: 'error message' },
      { level: :safe_log, severity: 'INFO', message: 'safe log message' },
    ].each do |test_case|
      it "logs with #{test_case[:level]} level" do
        with_stringio_logger(mode: :library) do |logger, io|
          logger.send(test_case[:level], test_case[:message])

          expect(io.string).to include(test_case[:severity], test_case[:message])
        end
      end
    end

    it 'handles runtime errors during logging' do
      logger = CovLoupe::Logger.new(target: 'stderr', mode: :cli)

      # Create a mock logger that will raise during send
      mock_stdlib_logger = instance_double(::Logger)
      allow(mock_stdlib_logger).to receive(:info).and_raise(StandardError.new('runtime error'))

      # Inject the mock logger
      logger.instance_variable_set(:@logger, mock_stdlib_logger)

      _result, _out, stderr_output = capture_io do
        logger.info('test message')
      end

      expect(stderr_output).to include('Warning: Configuration error: Unable to use log target')

      expect(File.exist?(fallback_file)).to be true
      content = File.read(fallback_file)
      expect(content).to include('MODE:cli', 'ERROR:runtime error', 'MSG:test message')
    end

    it 'handles a late logger-construction failure in CLI mode' do
      logger = CovLoupe::Logger.new(target: 'late-cli.log', mode: :cli)
      allow(logger).to receive(:build_logger).and_raise(Errno::EACCES, 'permission denied')

      stderr_output = capture_stderr { logger.info('late CLI failure') }

      expect(stderr_output).to include(
        'Warning: Configuration error: Unable to use log target',
        'See COV-LOUPE-LOG-ERROR.log for details.'
      )
      expect(File.read(fallback_file)).to include('MODE:cli', 'MSG:late CLI failure')
    end

    it 'wraps a late logger-construction failure as LoggingError' do
      logger = CovLoupe::Logger.new(target: 'late.log', mode: :mcp)
      allow(logger).to receive(:build_logger).and_raise(Errno::EACCES, 'permission denied')

      expect { logger.info('late failure') }
        .to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
      expect { logger.raise_if_initialization_failed! }
        .to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
    end
  end

  describe ':off sentinel disables logging' do
    let(:disabled_logger) { CovLoupe::Logger.new(target: ':off', mode: :cli) }

    it 'does not raise when logging methods are called' do
      expect { disabled_logger.info('test') }.not_to raise_error
      expect { disabled_logger.warn('test') }.not_to raise_error
      expect { disabled_logger.error('test') }.not_to raise_error
      expect { disabled_logger.safe_log('test') }.not_to raise_error
    end

    it 'does not create a log file' do
      disabled_logger.info('test message')
      expect(File.exist?('cov_loupe.log')).to be false
    end

    it 'does not write to fallback file' do
      disabled_logger.info('test message')
      expect(File.exist?(fallback_file)).to be false
    end

    context 'with case-insensitive handling' do
      it 'handles ":off" string with colon' do
        logger = CovLoupe::Logger.new(target: ':off', mode: :cli)
        expect { logger.info('test') }.not_to raise_error
        expect(File.exist?(fallback_file)).to be false
      end

      it 'handles ":OFF" (uppercase string with colon)' do
        logger = CovLoupe::Logger.new(target: ':OFF', mode: :cli)
        expect { logger.info('test') }.not_to raise_error
        expect(File.exist?(fallback_file)).to be false
      end
    end

    context 'with whitespace trimming' do
      it 'handles " :off " with surrounding whitespace' do
        logger = CovLoupe::Logger.new(target: '  :off  ', mode: :cli)
        expect { logger.info('test') }.not_to raise_error
        expect(File.exist?(fallback_file)).to be false
      end
    end

    context 'with non-sentinel values' do
      it '"off" without colon writes to file "off"' do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            logger = CovLoupe::Logger.new(target: 'off', mode: :cli)
            logger.info('test message')
            expect(File.exist?('off')).to be true
            expect(File.read('off')).to include('test message')
          end
        end
      end

      it '"OFF" without colon writes to file "OFF"' do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            logger = CovLoupe::Logger.new(target: 'OFF', mode: :cli)
            logger.info('test message')
            expect(File.exist?('OFF')).to be true
            expect(File.read('OFF')).to include('test message')
          end
        end
      end

      it '" off " without colon writes to file " off "' do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            logger = CovLoupe::Logger.new(target: ' off ', mode: :cli)
            logger.info('test message')
            expect(File.exist?(' off ')).to be true
          end
        end
      end
    end
  end
end
