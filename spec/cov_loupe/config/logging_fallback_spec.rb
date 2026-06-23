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
  end

  describe 'CovLoupe.logger error handling' do
    context 'when file logging fails in library mode' do
      it 'writes to fallback file but suppresses stderr' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_library,
          log_target:    '/invalid/path/that/does/not/exist.log',
          mode:          :library
        )

        stderr_output = nil
        CovLoupe.with_context(context) do
          _result, _out, stderr_output = capture_io do
            CovLoupe.logger.info('test message')
          end
        end

        expect(stderr_output).to be_empty
        expect(File.exist?(fallback_file)).to be true
        content = File.read(fallback_file)
        expect(content).to include('MODE:library', 'MSG:test message')
      end
    end

    context 'when file logging fails in CLI mode' do
      it 'writes to fallback file and prints warning to stderr exactly once' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_cli,
          log_target:    '/invalid/path/that/does/not/exist.log',
          mode:          :cli
        )

        stderr_output = nil
        CovLoupe.with_context(context) do
          capture_io do
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
        warning_msg = "Warning: Logging failed. See #{fallback_file} for details."
        expect(lines.count { |l| l.include?(warning_msg) }).to eq(1)

        # Check fallback file
        expect(File.exist?(fallback_file)).to be true
        content = File.read(fallback_file)
        expect(content).to include('MODE:cli', 'MSG:first failure', 'MSG:second failure')
      end
    end

    context 'when file logging fails in MCP server mode' do
      it 'writes to fallback file but suppresses stderr' do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
          log_target:    '/invalid/path/that/does/not/exist.log',
          mode:          :mcp
        )

        stderr_output = nil
        CovLoupe.with_context(context) do
          _result, _out, stderr_output = capture_io do
            CovLoupe.logger.info('test message')
          end
        end

        expect(stderr_output).to be_empty
        expect(File.exist?(fallback_file)).to be true
        content = File.read(fallback_file)
        expect(content).to include('MODE:mcp', 'MSG:test message')
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

      expect(stderr_output).to include("Warning: Logging failed. See #{fallback_file} for details.")

      expect(File.exist?(fallback_file)).to be true
      content = File.read(fallback_file)
      expect(content).to include('MODE:cli', 'ERROR:runtime error', 'MSG:test message')
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
