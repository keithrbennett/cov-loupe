# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::Logger do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def with_stringio_logger(mode: :library)
    io = StringIO.new
    stdlib_logger = ::Logger.new(io)
    stdlib_logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.iso8601}] #{severity}: #{msg}\n"
    end
    logger = described_class.new(target: 'stderr', mode: mode)
    logger.instance_variable_set(:@logger, stdlib_logger)
    yield logger, io
  end

  describe 'targets' do
    it 'rejects stdout at initialization' do
      expect { described_class.new(target: 'stdout', mode: :library) }
        .to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'accepts stderr case-insensitively and with surrounding whitespace' do
      logger = described_class.new(target: '  STDERR  ', mode: :library)
      io = StringIO.new
      logger.instance_variable_set(:@logger, ::Logger.new(io))

      logger.info('stderr message')

      expect(io.string).to include('stderr message')
      expect(File.exist?('  STDERR  ')).to be false
    end

    it 'defaults CLI and MCP logging to stderr' do
      %i[cli mcp].each do |mode|
        logger = described_class.new(target: nil, mode: mode)
        expect(logger.target).to eq('stderr')
      end
    end

    it 'defaults library logging to off' do
      logger = described_class.new(target: nil, mode: :library)

      expect(logger.target).to eq(':off')
      expect { logger.info('not emitted') }.not_to raise_error
      expect(File.exist?('cov_loupe.log')).to be false
    end

    it 'does not leave a persistent file until the first explicit file log' do
      logger = described_class.new(target: 'explicit.log', mode: :library)

      expect(File.exist?('explicit.log')).to be false
      logger.info('first message')

      expect(File.read('explicit.log')).to include('first message')
    end

    it 'probes an existing log file in append mode without truncating it' do
      File.write('existing.log', "previous content\n")

      logger = described_class.new(target: 'existing.log', mode: :library)

      expect(logger.instance_variable_get(:@init_error)).to be_nil
      expect(File.read('existing.log')).to eq("previous content\n")
    end

    it 'handles a race where another process creates the target during probing' do
      path = File.expand_path('race.log')
      open_flags = File::WRONLY | File::CREAT | File::EXCL
      allow(File).to receive(:exist?).with(path).and_return(false)
      allow(File).to receive(:open).with(path, open_flags, 0o644).and_raise(Errno::EEXIST)
      allow(File).to receive(:open).with(path, 'a').and_call_original

      logger = described_class.new(target: 'race.log', mode: :library)

      expect(logger.instance_variable_get(:@init_error)).to be_nil
    end

    it 'normalizes the :off sentinel with case and surrounding whitespace' do
      %w[:off :OFF].each do |target|
        logger = described_class.new(target: "  #{target}  ", mode: :cli)

        expect { logger.info('not emitted') }.not_to raise_error
        expect(logger.instance_variable_get(:@logger)).to be_nil
      end
    end

    it 'treats off without a colon as a literal file target' do
      %w[off OFF].each do |target|
        logger = described_class.new(target: target, mode: :cli)
        logger.info('literal target')

        expect(File.read(target)).to include('literal target')
      end
    end

    it 'treats a whitespace-wrapped off without a colon as a literal file target' do
      logger = described_class.new(target: ' off ', mode: :cli)
      logger.info('literal target')

      expect(File.read(' off ')).to include('literal target')
    end
  end

  describe 'target failures' do
    let(:invalid_target) { '/invalid/path/that/does/not/exist.log' }

    it 'raises during initialization in library mode' do
      expect { described_class.new(target: invalid_target, mode: :library) }
        .to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
    end

    it 'raises through an explicitly created library context' do
      expect do
        CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_library,
          log_target:    invalid_target,
          mode:          :library
        )
      end.to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
    end

    it 'warns during initialization in CLI mode' do
      stderr_output = capture_stderr do
        described_class.new(target: invalid_target, mode: :cli)
      end

      expect(stderr_output).to include('Warning: Configuration error: Unable to use log target')
    end

    it 'emits the CLI target warning only once' do
      stderr_output = capture_stderr do
        logger = described_class.new(target: invalid_target, mode: :cli)
        logger.info('first failure')
        logger.info('second failure')
      end

      warning = 'Warning: Configuration error: Unable to use log target'
      expect(stderr_output.scan(warning).length).to eq(1)
    end

    it 'does not create an implicit fallback file after a CLI write failure' do
      logger = described_class.new(target: 'late-cli.log', mode: :cli)
      allow(logger).to receive(:build_logger).and_raise(Errno::EACCES, 'permission denied')

      stderr_output = capture_stderr { logger.info('late CLI failure') }

      expect(stderr_output).to include('Warning: Configuration error: Unable to use log target')
      expect(File.exist?('COV-LOUPE-LOG-ERROR.log')).to be false
    end

    it 'raises on a late write failure in MCP mode without a fallback file' do
      logger = described_class.new(target: 'late.log', mode: :mcp)
      allow(logger).to receive(:build_logger).and_raise(Errno::EACCES, 'permission denied')

      expect { logger.info('late failure') }
        .to raise_error(CovLoupe::LoggingError, /Unable to use log target/)
      expect(File.exist?('COV-LOUPE-LOG-ERROR.log')).to be false
    end

    it 'preserves the original MCP operation error when logging fails' do
      logger = described_class.new(target: 'late.log', mode: :mcp)
      allow(logger).to receive(:build_logger).and_raise(Errno::EACCES, 'permission denied')
      context = CovLoupe.create_context(
        error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
        log_target:    'late.log',
        mode:          :mcp
      ).with(logger: logger)

      response = CovLoupe.with_context(context) do
        CovLoupe::BaseTool.with_error_handling('test_tool', error_mode: :log) do
          raise 'business error'
        end
      end

      expect(response.content.first['text']).to include('business error')
      expect(response.content.first['text']).not_to include('Unable to use log target')
    end

    it 'does not propagate runtime logging failures through safe_log' do
      logger = described_class.new(target: 'stderr', mode: :library)
      failing_logger = instance_double(::Logger)
      allow(failing_logger).to receive(:info).and_raise(StandardError, 'runtime error')
      logger.instance_variable_set(:@logger, failing_logger)

      expect { logger.safe_log('best effort') }.not_to raise_error
      expect(File.exist?('COV-LOUPE-LOG-ERROR.log')).to be false
    end
  end

  describe ':off' do
    it 'does not raise or create files' do
      logger = described_class.new(target: ':off', mode: :cli)

      expect { logger.info('test') }.not_to raise_error
      expect { logger.safe_log('test') }.not_to raise_error
      expect(File.exist?('cov_loupe.log')).to be false
      expect(File.exist?('COV-LOUPE-LOG-ERROR.log')).to be false
    end
  end

  describe 'log levels' do
    [
      [:info, 'INFO', 'info message'],
      [:warn, 'WARN', 'warning message'],
      [:error, 'ERROR', 'error message'],
      [:safe_log, 'INFO', 'safe log message'],
    ].each do |level, severity, message|
      it "logs with #{level}" do
        with_stringio_logger do |logger, io|
          logger.public_send(level, message)

          expect(io.string).to include(severity, message)
        end
      end
    end
  end
end
