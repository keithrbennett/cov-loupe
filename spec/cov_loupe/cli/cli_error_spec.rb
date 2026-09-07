# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe CovLoupe::CoverageCLI do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  it 'shows help and exits 0' do
    out, err, status = run_cli_with_status('--help')
    expect(status).to eq(0)
    expect(err).to eq('')
    [
      %r{Usage:\s+cov-loupe \[options\] \[subcommand\] \[args\]\s+\(default subcommand: list\)},
      %r{Repository:\s+https://github.com/keithrbennett/cov-loupe},
      %r{Documentation \(Web\):\s+https://keithrbennett.github.io/cov-loupe/},
      %r{Documentation \(Local\):\s+},
      %r{Screencast:\s+https://www.bbs-software.com/screencasts/cov-loupe},
      %r{Version:\s+#{CovLoupe::VERSION}},
    ].each do |pattern|
      expect(out).to match(pattern)
    end
  end

  shared_examples 'maps error to exit 1 with message' do
    before do
      # Build a fake model that raises the specified error from the specified method
      fake_model = Class.new do
        def initialize(*)
        end
      end
      error_to_raise = raised_error
      fake_model.define_method(model_method) { |*| raise error_to_raise }
      stub_const('CovLoupe::CoverageModel', fake_model)
    end

    it 'exits with status 1 and friendly message' do
      _out, err, status = run_fixture_cli_with_status(*invoke_args)
      expect(status).to eq(1)
      expect(err).to include(expected_message)
    end
  end

  context 'when mapping ENOENT' do
    let(:model_method) { :summary_for }
    let(:raised_error) { Errno::ENOENT.new('No such file or directory @ rb_sysopen - missing.rb') }
    let(:invoke_args) { ['summary', 'lib/missing.rb'] }
    let(:expected_message) { 'File error: File not found: lib/missing.rb' }

    it_behaves_like 'maps error to exit 1 with message'
  end

  context 'when mapping EACCES' do
    let(:model_method) { :raw_for }
    let(:raised_error) { Errno::EACCES.new('Permission denied @ rb_sysopen - secret.rb') }
    let(:invoke_args) { ['raw', 'lib/secret.rb'] }
    let(:expected_message) { 'Permission denied: lib/secret.rb' }

    it_behaves_like 'maps error to exit 1 with message'
  end

  it 'emits detailed stale coverage info and exits 1' do
    mock_coverage_with_timestamp(root, VERY_OLD_TIMESTAMP, coverage: {
      File.join(root, 'lib', 'foo.rb') => { 'lines' => [1, 0, 1] },
    })

    _out, err, status = run_fixture_cli_with_status('--raise-on-stale=yes', 'summary', 'lib/foo.rb')
    expect(status).to eq(1)
    expect(err).to include('Coverage data stale:')
    expect(err).to match(/File\s+- time:/)
    expect(err).to match('Coverage\s+- time:')
    expect(err).to match(/Delta\s+- file is [+-]?\d+s newer than coverage/)
    expect(err).to match('Coverage file\s+-')
  end

  it 'honors --raise-on-stale=false to disable checks' do
    mock_coverage_with_timestamp(root, VERY_OLD_TIMESTAMP, coverage: {
      File.join(root, 'lib', 'foo.rb') => { 'lines' => [1, 0, 1] },
    })

    _out, err, status = run_fixture_cli_with_status('--raise-on-stale=false', 'summary',
      'lib/foo.rb')
    expect(status).to eq(0)
    expect(err).to eq('')
  end

  it 'handles source rendering errors gracefully with fallback message' do
    # Test that source rendering with problematic coverage data doesn't crash
    # This is a regression test for the "can't convert nil into Integer" crash
    # that was previously mentioned in comments
    out, err, status = run_fixture_cli_with_status(
      '--source', 'uncovered', '--context-lines', '2', '--color=false', 'uncovered', 'lib/foo.rb'
    )

    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to match(%r{File:\s+lib/foo\.rb})
    expect(out).to include('│') # Table format
    expect(out).to show_source_table_or_fallback
  end

  it 'renders source with full mode without crashing' do
    # Additional regression test for source rendering with full mode
    out, err, status = run_fixture_cli_with_status(
      '--source', 'full', '--color=false', 'summary', 'lib/foo.rb'
    )

    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to include('lib/foo.rb')
    expect(out).to include('66.67%')
    expect(out).to show_source_table_or_fallback
  end

  describe 'deleted file handling' do
    let(:foo_path) { File.join(root, 'lib', 'foo.rb') }
    let(:temp_path) { "#{foo_path}.hidden" }
    let(:file_based_subcommands) { %w[summary raw uncovered detailed] }

    before do
      File.rename(foo_path, temp_path) if File.exist?(foo_path)
    end

    after do
      File.rename(temp_path, foo_path) if File.exist?(temp_path)
    end

    it 'returns coverage data for deleted file with raise_on_stale=false (default)' do
      # Test all file-based subcommands return coverage data for deleted files
      file_based_subcommands.each do |subcommand|
        # Build args dynamically based on subcommand
        args = if subcommand == 'raw'
          # Raw command shows array format without --source full
          ['--format', 'json', subcommand, 'lib/foo.rb']
        else
          # Other commands use --source full for table format
          ['--source', 'full', '--color=false', subcommand, 'lib/foo.rb']
        end

        out, err, status = run_fixture_cli_with_status(*args)

        expect(status).to eq(0), "Subcommand #{subcommand} should exit with status 0"
        expect(err).to eq('')
        expect(out).to include('lib/foo.rb')

        # Subcommand-specific expectations
        case subcommand
        when 'summary'
          expect(out).to include('66.67%')
        when 'raw'
          # Raw command with JSON format shows the lines array
          data = JSON.parse(out)
          expect(data['lines']).to eq([nil, nil, 1, 0, nil, 2])
        when 'uncovered'
          expect(out).to include('2')
        when 'detailed'
          # Detailed shows table with Line, Hits, Covered columns
          expect(out).to include('│', 'Line', 'Hits', 'Covered', '[source not available]')
        end
      end
    end

    it 'raises error when querying deleted file with raise_on_stale=true' do
      # Test all file-based subcommands raise error for deleted files in strict mode
      file_based_subcommands.each do |subcommand|
        _out, err, status = run_fixture_cli_with_status(
          '--raise-on-stale=yes',
          '--source', 'full', '--color=false', subcommand, 'lib/foo.rb'
        )

        expect(status).to eq(1), "Subcommand #{subcommand} should exit with status 1"
        expect(err).to include('File not found')
        expect(err).to include('lib/foo.rb')
      end
    end
  end

  describe 'invalid option handling' do
    invalid_option_cases = {
      '--subcommand-like suggestion'     => {
        args:              ['--summary'],
        expected_messages: [
          "Error: '--summary' is not a valid option. Did you mean the 'summary' subcommand?",
          'Try: cov-loupe summary [args]',
        ],
      },
      '--error-mode=bogus (enum with =)' => {
        args:              ['--error-mode=bogus', 'list'],
        expected_messages: ['invalid argument: --error-mode=bogus'],
      },
      '--error-mode bogus (enum space)'  => {
        args:              ['--error-mode', 'bogus', 'list'],
        expected_messages: ['invalid argument: bogus'],
      },
      '--no-such-option'                 => {
        args:              ['--no-such-option'],
        expected_messages: ['Error: invalid option: --no-such-option'],
      },
      '--context-lines negative'         => {
        args:              ['--context-lines', '-1', 'summary', 'lib/foo.rb'],
        expected_messages: ['Context lines cannot be negative'],
      },
    }

    invalid_option_cases.each do |description, test_case|
      it description do
        _out, err, status = run_cli_with_status(*test_case[:args])
        expect(status).to eq(1)
        test_case[:expected_messages].each { |msg| expect(err).to include(msg) }
      end
    end
  end

  describe 'subcommand error handling' do
    it 'handles generic exceptions from subcommands' do
      # Stub the CommandFactory to return a command that raises a StandardError
      fake_command = Class.new do
        def initialize(_cli) = nil
        def execute(_args) = raise(StandardError, 'Unexpected error in subcommand')
      end

      allow(CovLoupe::Commands::CommandFactory).to receive(:create)
        .and_return(fake_command.new(nil))

      _out, err, status = run_fixture_cli_with_status('summary', 'lib/foo.rb')
      expect(status).to eq(1)
      expect(err).to include('Unexpected error in subcommand')
    end
  end
end
