# frozen_string_literal: true

require 'spec_helper'
require 'shellwords'
require 'tempfile'

RSpec.describe CovLoupe::CoverageCLI do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  it 'errors with usage when summary path is missing' do
    _out, err, status = run_fixture_cli_with_status('summary')
    expect(status).to eq(2)
    expect(err).to include('Usage: cov-loupe summary <path>')
  end

  it 'errors with meaningful message for unknown subcommand' do
    _out, err, status = run_fixture_cli_with_status('bogus')
    expect(status).to eq(2)
    expect(err).to include("Unknown subcommand: 'bogus'", 'Valid subcommands:')
  end

  it 'list honors stale=error and tracked_globs by exiting 1 when project is stale' do
    Tempfile.create(%w[brand_new_file_for_cli_usage_spec .rb], File.join(root, 'lib')) do |f|
      f.write("# new file\n")
      f.flush
      _out, err, status = run_fixture_cli_with_status(
        '--raise-on-stale', 'true', '--tracked-globs', 'lib/**/*.rb', 'list'
      )
      expect(status).to eq(1)
      expect(err).to include('Coverage data stale (project)')
    end
  end

  it 'list with stale=off prints table and exits 0' do
    out, err, status = run_fixture_cli_with_status('--raise-on-stale=false', 'list')
    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to include('File', 'lib/foo.rb')
  end

  describe 'misplaced global options detection' do
    [
      { args: ['list', '--format', 'json'],               expected: '--format' },
      { args: ['summary', 'lib/foo.rb', '--format=json'], expected: '--format=json' },
      { args: ['list', '--coverage-file=path/to/file'],       expected: '--coverage-file=' },
      { args: ['list', '--mode', 'mcp'],                  expected: '--mode' },
      { args: ['list', '-m', 'cli'],                      expected: '-m' },
      { args: ['summary', 'lib/foo.rb', '--mode=mcp'],    expected: '--mode=mcp' },
      { args: ['list', '--allow-code-predicates'],        expected: '--allow-code-predicates' },
      { args: ['list', '--no-allow-code-predicates'],     expected: '--no-allow-code-predicates' },
    ].each do |test_case|
      it "detects misplaced #{test_case[:expected]} option after subcommand" do
        _out, err, status = run_fixture_cli_with_status(*test_case[:args])
        expect(status).to eq(2)
        expect(err).to include('Global option(s) must come BEFORE the subcommand')
        expect(err).to include(test_case[:expected])
      end
    end
  end

  describe 'misplaced global option hint' do
    [
      [%w[totals --format json], 'cov-loupe totals --format json',
        'cov-loupe --format json totals'],
      [%w[totals --format=json], 'cov-loupe totals --format=json',
        'cov-loupe --format=json totals'],
      [%w[totals -f json -S], 'cov-loupe totals -f json -S',
        'cov-loupe -f json -S <BOOLEAN> totals'],
      [%w[totals -e], 'cov-loupe totals -e',
        'cov-loupe -e <MODE> totals'],
      [%w[totals -e -f json], 'cov-loupe totals -e -f json',
        'cov-loupe -e <MODE> -f json totals'],
      [%w[totals --no-allow-code-predicates], 'cov-loupe totals --no-allow-code-predicates',
        'cov-loupe --no-allow-code-predicates totals'],
      [%w[-R proj totals --format json], 'cov-loupe -R proj totals --format json',
        'cov-loupe -R proj --format json totals'],
      [%w[-- totals --format json], 'cov-loupe -- totals --format json',
        'cov-loupe --format json -- totals'],
      [%w[-g -- totals --format json], 'cov-loupe -g -- totals --format json',
        'cov-loupe -g -- --format json totals'],
      [['summary', 'lib/my file.rb', '-f', 'json'], "cov-loupe summary 'lib/my file.rb' -f json",
        "cov-loupe -f json summary 'lib/my file.rb'"],
      [['validate', '-i', '->(m) { true }', '-f', 'json'], "cov-loupe validate -i '->(m) { true }' -f json",
        "cov-loupe -f json validate -i '->(m) { true }'"],
      [['summary', "lib/it's.rb", '-f', 'json'], "cov-loupe summary 'lib/it'\\''s.rb' -f json",
        "cov-loupe -f json summary 'lib/it'\\''s.rb'"],
    ].each do |args, used, correct|
      it "suggests `#{correct}` for `#{used}`" do
        _out, err, status = run_cli_with_status(*args)
        expect(status).to eq(2)
        expect(err).to include("You used: #{used}\n", "Correct: #{correct}\n")
      end

      next if correct.include?('<') # placeholders are for the user to fill in

      it "accepts the suggested `#{correct}`" do
        cli = described_class.new
        cli.send(:parse_options!, Shellwords.split(correct).drop(1))
        cmd, cmd_args = cli.instance_variable_get(:@cmd), cli.instance_variable_get(:@cmd_args)
        expect(cmd).to eq(args.find { |arg| CovLoupe::SUBCOMMANDS.include?(arg) })
        expect { cli.send(:check_for_misplaced_global_options, cmd, cmd_args) }.not_to raise_error
      end
    end

    it 'quotes arguments so the suggested command splits back into the same arguments' do
      args = ['validate', '-i', %q(->(m) { m.list.none? { |f| f['file'] == "it's.rb" } }), '-f', 'json']
      _out, err, _status = run_cli_with_status(*args)
      correct = err[/^Correct: (.*)$/, 1]
      expect(Shellwords.split(correct)).to eq(['cov-loupe', '-f', 'json', *args.first(3)])
    end

    it 'leaves out COV_LOUPE_OPTS arguments, which the user did not type' do
      original = ENV.fetch('COV_LOUPE_OPTS', nil)
      ENV['COV_LOUPE_OPTS'] = '-g lib/**/*.rb'
      _out, err, status = run_full_cli_with_status('totals', '--format', 'json')
      expect(status).to eq(2)
      expect(err).to include("You used: cov-loupe totals --format json\n",
        "Correct: cov-loupe --format json totals\n")
    ensure
      ENV['COV_LOUPE_OPTS'] = original
    end
  end

  describe 'stderr output' do
    let(:missing_message) { 'Could not find coverage.json' }

    it 'writes nothing to stderr on a successful run logging to stderr' do
      out, err, status = run_fixture_cli_with_status('--log-file', 'stderr', '--format', 'json', 'totals')
      expect(status).to eq(0)
      expect(out).not_to be_empty
      expect(err).to eq('')
    end

    it 'prints a missing coverage file error to stderr exactly once' do
      Dir.mktmpdir do |dir|
        _out, err, status = run_cli_with_status('--log-file', 'stderr', '--root', dir, 'totals')
        expect(status).to eq(1)
        expect(err.scan(missing_message).size).to eq(1)
        expect(err).not_to include('CLI parameters', 'Error in CLI')
      end
    end

    it 'prints the error once with its full stack trace in debug mode' do
      Dir.mktmpdir do |dir|
        _out, err, status = run_cli_with_status('--log-file', 'stderr', '--error-mode', 'debug',
          '--root', dir, 'totals')
        expect(status).to eq(1)
        expect(err.scan(missing_message).size).to eq(1)
        expect(err).not_to include('ERROR: Error in CLI')
        expect(err.lines.grep(/\.rb:\d+:in /).size).to be > 5 # more than the 5 frames shown with a log file
      end
    end

    it 'leaves paths unchanged with --output-chars ascii' do
      with_utf8_default_external do
        Dir.mktmpdir do |dir|
          root = File.join(dir, "proj\u00e9\u2192")
          Dir.mkdir(root)
          _out, err, status = run_cli_with_status('--log-file', 'stderr', '--output-chars', 'ascii',
            '--root', root, 'totals')
          expect(status).to eq(1)
          expect(err).to include(missing_message, "proj\u00e9\u2192")
        end
      end
    end

    it 'writes the parameters line and the error to a log file' do
      Dir.mktmpdir do |dir|
        log_path = File.join(dir, 'cov-loupe.log')
        _out, err, status = run_cli_with_status('--log-file', log_path, '--root', dir, 'totals')
        expect(status).to eq(1)
        expect(err.scan(missing_message).size).to eq(1)

        log = File.read(log_path)
        expect(log).to include('INFO: CLI parameters:')
        expect(log).to match(/subcommand\W+"totals"/) # Hash#inspect format differs before Ruby 3.4
        expect(log).to include("ERROR: Error in CLI: CovLoupe::CoverageFileNotFoundError: #{missing_message}")
        expect(log.scan(missing_message).size).to eq(1)
      end
    end

    context 'with an unexpected error in a subcommand' do
      before do
        failing_command = instance_double(CovLoupe::Commands::TotalsCommand)
        allow(failing_command).to receive(:execute).and_raise(RuntimeError, 'boom')
        allow(CovLoupe::Commands::CommandFactory).to receive(:create).and_return(failing_command)
      end

      it 'prints it to stderr exactly once' do
        _out, err, status = run_fixture_cli_with_status('--log-file', 'stderr', 'totals')
        expect(status).to eq(1)
        expect(err.scan('boom').size).to eq(1)
        expect(err).to include('An unexpected error occurred: boom')
      end

      it 'logs the original error to the log file exactly once' do
        Dir.mktmpdir do |dir|
          log_path = File.join(dir, 'cov-loupe.log')
          _out, _err, status = run_fixture_cli_with_status('--log-file', log_path, 'totals')
          expect(status).to eq(1)

          log = File.read(log_path)
          expect(log).to include("ERROR: Error in subcommand 'totals': RuntimeError: boom")
          expect(log.scan('boom').size).to eq(1)
        end
      end
    end

    context 'with a cov-loupe error in the default report' do
      it 'prints its friendly message without a backtrace' do
        Dir.mktmpdir do |dir|
          _out, err, status = run_cli_with_status('--root', dir)
          expect(status).to eq(1)
          expect(err).to start_with('File error: Could not find coverage.json')
          expect(err).not_to include('.rb:')
        end
      end
    end

    # As when writing non-ASCII output to a stream that transcodes to US-ASCII
    context 'with an encoding error while reporting' do
      before do
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new)
          .and_raise(Encoding::UndefinedConversionError, 'U+00E9 from UTF-8 to US-ASCII')
      end

      { 'the list subcommand' => ['list'], 'the default report' => [] }.each do |desc, args|
        it "reports a text encoding error without blaming the coverage data, for #{desc}" do
          _out, err, status = run_fixture_cli_with_status(*args)
          expect(status).to eq(1)
          expect(err).to start_with('Text encoding error: U+00E9 from UTF-8 to US-ASCII.')
          expect(err).not_to include('coverage data')
        end
      end
    end

    # Through the full entry point, as the cov-loupe executable runs it
    context 'with an unknown subcommand' do
      it 'prints it to stderr exactly once' do
        _out, err, status = run_full_cli_with_status('--log-file', 'stderr', 'bogus')
        expect(status).to eq(2)
        expect(err.scan('Unknown subcommand').size).to eq(1)
      end

      it 'logs it to the --log-file given before it' do
        Dir.mktmpdir do |dir|
          log_path = File.join(dir, 'cov-loupe.log')
          _out, err, status = run_full_cli_with_status('--log-file', log_path, 'bogus')
          expect(status).to eq(2)
          expect(err).to include('Unknown subcommand')
          expect(File.read(log_path))
            .to include('ERROR: Error in CLI: CovLoupe::UsageError: Unknown subcommand')
        end
      end
    end

    it 'does not log an error raised while options are still being parsed' do
      Dir.mktmpdir do |dir|
        log_path = File.join(dir, 'cov-loupe.log')
        _out, err, status = run_cli_with_status('--log-file', log_path, '--context-lines', '-1', 'totals')
        expect(status).to eq(2)
        expect(err).to include('Context lines cannot be negative')
        expect(File.exist?(log_path)).to be false
      end
    end

    it 'reports an invalid option value only on stderr, before logging is set up' do
      Dir.mktmpdir do |dir|
        log_path = File.join(dir, 'cov-loupe.log')
        _out, err, status = run_full_cli_with_status('--log-file', log_path, '--format', 'nope', 'list')
        expect(status).to eq(2)
        expect(err.scan('Error: invalid argument').size).to eq(1)
        expect(File.exist?(log_path)).to be false
      end
    end
  end

  describe 'with a custom error handler that implements only handle_error' do
    let(:handler_class) do
      Class.new do
        attr_reader :handled

        def initialize = @handled = []

        def handle_error(error, context: nil, reraise: true)
          @handled << [error, context]
          raise error if reraise
        end
      end
    end
    let(:handler) { handler_class.new }

    before do
      failing_command = instance_double(CovLoupe::Commands::TotalsCommand)
      allow(failing_command).to receive(:execute).and_raise(RuntimeError, 'boom')
      allow(CovLoupe::Commands::CommandFactory).to receive(:create).and_return(failing_command)
    end

    def run_with_handler(*argv)
      status = nil
      _result, _out, err = capture_io do
        described_class.new(error_handler: handler).run(fixture_cli_args(*argv))
      rescue SystemExit => e
        status = e.status
      end
      [err, status]
    end

    # Unlike the built-in handler, a custom one is called whatever the log target.
    %w[stderr off file].each do |target|
      it "passes an unexpected error to the handler with a #{target} log target" do
        Dir.mktmpdir do |dir|
          log_target = target == 'file' ? File.join(dir, 'cov-loupe.log') : target
          err, status = run_with_handler('--log-file', log_target, 'totals')
          expect(status).to eq(1)
          expect(err.scan('An unexpected error occurred: boom').size).to eq(1)
          expect(handler.handled.map(&:last)).to eq(["subcommand 'totals'"])
        end
      end
    end

    it "uses the handler's convert_standard_error when it provides one" do
      handler.define_singleton_method(:convert_standard_error) do |error|
        CovLoupe::FileError.new("converted: #{error.message}", error)
      end
      err, status = run_with_handler('--log-file', 'stderr', 'totals')
      expect(status).to eq(1)
      expect(err).to include('converted: boom')
      expect(err).not_to include('An unexpected error occurred')
    end
  end

  describe 'extra arguments detection' do
    it 'rejects extra arguments to list command' do
      _out, err, status = run_fixture_cli_with_status('list', 'extra')
      expect(status).to eq(2)
      expect(err).to include('Unexpected argument')
      expect(err).to include('extra')
    end

    it 'rejects extra arguments after path in summary command' do
      _out, err, status = run_fixture_cli_with_status('summary', 'lib/foo.rb', 'extra')
      expect(status).to eq(2)
      expect(err).to include('Unexpected argument')
      expect(err).to include('extra')
    end
  end
end
