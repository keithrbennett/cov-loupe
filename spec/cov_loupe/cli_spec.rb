# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe CovLoupe::CoverageCLI do
  let(:fixture_root) { File.dirname(FIXTURE_PROJECT1_RESULTSET_PATH, 2) }

  # Windows refuses to delete a temporary directory while a file handle inside it
  # remains open, so we ensure the logger (and its file) are closed after each use.
  # We do this so that the tests will run on Windows (including for CI),
  # but this workaround should not be necessary for a Windows production system
  # since the log file is not created by Dir.mktmpdir.
  def with_temp_cli_log_file(file_name = 'custom.log')
    Dir.mktmpdir do |dir|
      log_path = File.join(dir, file_name)
      captured_std_logger = nil
      begin
        yield log_path, ->(logger) { captured_std_logger = logger.instance_variable_get(:@logger) }
      ensure
        captured_std_logger&.close
      end
    end
  end

  def run_cli(*argv)
    run_fixture_cli_output(*argv)
  end

  describe 'JSON output' do
    def with_json_output(command, *args)
      output = run_cli('--format', 'json', command, *args)
      yield JSON.parse(output)
    end

    [
      { cmd: 'summary', args: ['lib/foo.rb'], key: 'summary', check: ->(d) {
        d['summary']['covered'] == 2
      } },
      { cmd: 'raw', args: ['lib/foo.rb'], key: 'lines', check: ->(d) {
        d['lines'] == [nil, nil, 1, 0, nil, 2]
      } },
      { cmd: 'uncovered', args: ['lib/foo.rb'], key: 'uncovered', check: ->(d) {
        d['uncovered'] == [4]
      } },
      { cmd: 'detailed', args: ['lib/foo.rb'], key: 'lines', check: ->(d) {
        d['lines'].is_a?(Array)
      } },
    ].each do |tc|
      it "prints #{tc[:cmd]} as JSON" do
        with_json_output(tc[:cmd], *tc[:args]) do |data|
          expect(tc[:check].call(data)).to be true
        end
      end
    end

    it 'prints totals as JSON' do
      with_json_output('totals') do |data|
        expect(data['lines']).to include(
          'total'      => 6,
          'covered'    => 3,
          'uncovered'  => 3,
          'percentage' => be_within(0.01).of(50.0)
        )
        expect(data['tracking']).to include('enabled' => false)
        expect(data['files']).to include('total' => 2)
        expect(data['files']['with_coverage']).to include('total' => 2, 'ok' => 2)
      end
    end
  end

  describe 'subcommand abbreviations' do
    [
      { abbrev: 'd', full: 'detailed',  args: ['lib/foo.rb'] },
      { abbrev: 'l', full: 'list',      args: [] },
      { abbrev: 'r', full: 'raw',       args: ['lib/foo.rb'] },
      { abbrev: 's', full: 'summary',   args: ['lib/foo.rb'] },
      { abbrev: 't', full: 'totals',    args: [] },
      { abbrev: 'u', full: 'uncovered', args: ['lib/foo.rb'] },
      { abbrev: 'v', full: 'validate',  args: ['-i', '->(m) { true }'] },
    ].each do |tc|
      it "resolves '#{tc[:abbrev]}' to '#{tc[:full]}'" do
        _stdout, _stderr, status = run_fixture_cli_with_status(tc[:abbrev], *tc[:args])
        expect(status).to eq(0)
      end
    end
  end

  it 'prints raw lines as text' do
    output = run_cli('raw', 'lib/foo.rb')
    expect(output).to include('File: lib/foo.rb', '│') # Table format
  end

  it 'list subcommand with --json outputs JSON with sort order' do
    output = run_cli(
      '--format', 'json', '--sort-order', 'a', 'list'
    )
    asc = JSON.parse(output)
    expect(asc['files']).to be_an(Array)
    expect(asc['files'].first['file']).to end_with('lib/bar.rb')

    # Includes counts for total/ok/stale and they are consistent
    expect(asc['counts']).to include('total', 'ok', 'stale')
    total = asc['counts']['total']
    ok = asc['counts']['ok']
    stale = asc['counts']['stale']
    expect(total).to eq(asc['files'].length)
    expect(ok + stale).to eq(total)

    output = run_cli(
      '--format', 'json', '--sort-order', 'd', 'list'
    )
    desc = JSON.parse(output)
    expect(desc['files'].first['file']).to end_with('lib/foo.rb')
  end

  it 'list subcommand outputs formatted table' do
    output = run_cli('list')
    expect(output).to include('File', 'lib/foo.rb', 'lib/bar.rb')
    expect(output).to match(/Files: total \d+/)
  end

  it 'list subcommand retains rows when using an absolute tracked glob' do
    absolute_glob = File.join(fixture_root, 'lib', '**', '*.rb')
    output = run_cli('--tracked-globs',
      absolute_glob, 'list')
    expect(output).not_to include('No coverage data found')
    expect(output).to include('lib/foo.rb', 'lib/bar.rb')
  end

  it 'totals subcommand prints a readable summary by default' do
    output = run_cli('totals')
    expect(output).to include('Lines')
  end

  it 'can include source in JSON payload (nil if file missing)' do
    output = run_cli('--format', 'json', '--source', 'full', 'summary', 'lib/foo.rb')
    data = JSON.parse(output)
    expect(data).to have_key('source')
  end

  describe 'log file configuration' do
    it 'passes --log-file path into the CLI execution context' do
      original_target = CovLoupe.active_log_file
      with_temp_cli_log_file do |log_path, capture_logger|
        expect(CovLoupe).to receive(:create_context)
          .and_wrap_original do |m, error_handler:, log_target:, mode:|
          # Ensure CLI forwards the requested log path into the context without changing other fields.
          expect(log_target).to eq(log_path)
          context = m.call(error_handler: error_handler, log_target: log_target, mode: mode)
          capture_logger.call(context.logger)
          context
        end
        run_cli('--format', 'json', '--log-file', log_path, 'summary', 'lib/foo.rb')
        expect(CovLoupe.active_log_file).to eq(original_target)
      end
    end

    it 'rejects stdout logging in the CLI context' do
      original_target = CovLoupe.active_log_file
      _stdout, stderr, status = run_cli_with_status(
        '--format', 'json', '--log-file', 'stdout', 'summary', 'lib/foo.rb'
      )
      expect(status).to eq(1)
      expect(stderr).to include('stdout', 'not permitted')
      expect(CovLoupe.active_log_file).to eq(original_target)
    end

    it 'supports :off sentinel to disable logging' do
      expect(CovLoupe).to receive(:create_context)
        .and_wrap_original do |m, error_handler:, log_target:, mode:|
        expect(log_target).to eq(':off')
        m.call(error_handler: error_handler, log_target: log_target, mode: mode)
      end
      run_cli('--format', 'json', '--log-file', ':off', 'summary', 'lib/foo.rb')
    end

    it 'supports case-insensitive :off sentinel' do
      expect(CovLoupe).to receive(:create_context)
        .and_wrap_original do |m, error_handler:, log_target:, mode:|
        expect(log_target).to eq(':OFF')
        m.call(error_handler: error_handler, log_target: log_target, mode: mode)
      end
      run_cli('--format', 'json', '--log-file', ':OFF', 'summary', 'lib/foo.rb')
    end

    it 'supports whitespace-trimmed :off sentinel' do
      expect(CovLoupe).to receive(:create_context)
        .and_wrap_original do |m, error_handler:, log_target:, mode:|
        expect(log_target).to eq('  :off  ')
        m.call(error_handler: error_handler, log_target: log_target, mode: mode)
      end
      run_cli('--format', 'json', '--log-file', '  :off  ', 'summary', 'lib/foo.rb')
    end

    it 'actually disables logging when --log-file :off is used' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          logger = CovLoupe::Logger.new(target: ':off', mode: :cli)
          logger.info('test message')
          expect(File.exist?('cov_loupe.log')).to be false
          expect(File.exist?('COV-LOUPE-LOG-ERROR.log')).to be false
        end
      end
    end
  end

  describe 'version reporting' do
    %w[-v --version].each do |flag|
      it "#{flag} prints bare version string and exits" do
        output = run_cli(flag)
        expect(output.strip).to eq(CovLoupe::VERSION)
      end
    end

    # The version subcommand was removed in v5.0.0
    it 'version subcommand is no longer recognized' do
      _stdout, stderr, status = run_fixture_cli_with_status('version')
      expect(status).to eq(1)
      expect(stderr).to include("Unknown subcommand: 'version'")
    end
  end

  describe 'resource value retrieval' do
    %w[-p --path-for].each do |flag|
      {
        'repo' => 'https://github.com/keithrbennett/cov-loupe',
        'docs' => 'https://keithrbennett.github.io/cov-loupe/',
      }.each do |resource, expected_value|
        it "returns value for canonical resource '#{resource}' with #{flag}" do
          output = run_cli(flag, resource)
          expect(output.strip).to eq(expected_value)
        end
      end

      it "returns local README path for docs-local with #{flag}" do
        output = run_cli(flag, 'docs-local')
        expect(output.strip).to end_with('README.md')
      end

      it "exits with error for unknown resource with #{flag}" do
        _out, err, status = run_cli_with_status(flag, 'unknown')
        expect(status).to eq(1)
        expect(err).to include("Unknown resource: 'unknown'")
      end

      it "exits early and ignores other options with #{flag}" do
        output = run_cli(flag, 'repo', '--format', 'json', 'list')
        expect(output.strip).to eq('https://github.com/keithrbennett/cov-loupe')
      end
    end
  end

  describe 'exclusions summary' do
    it 'displays all types of exclusions on stderr' do
      presenter_double = instance_double(
        CovLoupe::Presenters::ProjectCoveragePresenter,
        relative_newer_files:           ['newer.rb'],
        relative_length_mismatch_files: ['mismatch.rb'],
        relative_unreadable_files:      ['unreadable.rb'],
        relative_missing_tracked_files: [],
        relative_deleted_files:         [],
        relative_skipped_files:         [],
        relative_files:                 [],
        timestamp_status:               'ok'
      )
      allow(CovLoupe::Presenters::ProjectCoveragePresenter)
        .to receive(:new).and_return(presenter_double)

      _stdout, stderr, _status = run_fixture_cli_with_status('list')

      expect(stderr).to include(
        'Files newer than coverage',
        'newer.rb',
        'Line count mismatches',
        'mismatch.rb',
        'Unreadable files',
        'unreadable.rb'
      )
    end
  end

  describe 'timestamp warning' do
    def stub_presenter_with_timestamp_status(status, include_model: false)
      presenter_double = instance_double(
        CovLoupe::Presenters::ProjectCoveragePresenter,
        relative_newer_files:           [],
        relative_length_mismatch_files: [],
        relative_unreadable_files:      [],
        relative_missing_tracked_files: [],
        relative_deleted_files:         [],
        relative_skipped_files:         [],
        relative_files:                 [],
        timestamp_status:               status,
        relativized_payload:            { 'files' => [], 'counts' => {} }
      )
      allow(CovLoupe::Presenters::ProjectCoveragePresenter)
        .to receive(:new).and_return(presenter_double)

      return unless include_model

      model_double = instance_double(
        CovLoupe::CoverageModel,
        format_table: "Coverage Table\n",
        list:         { 'files' => [], 'timestamp_status' => status },
        skipped_rows: []
      )
      allow(CovLoupe::CoverageModel).to receive(:new).and_return(model_double)
    end

    it 'outputs warning to stderr when timestamps are missing' do
      stub_presenter_with_timestamp_status('missing', include_model: true)

      [[], %w[--format json]].each do |args|
        _stdout, stderr, _status = run_fixture_cli_with_status(*args)

        expect(stderr).to include(
          'WARNING: Coverage timestamps are missing.',
          'Time-based staleness checks were skipped.',
          'Files may appear "ok" even if source code is newer than the coverage data.',
          'Check your coverage tool configuration to ensure timestamps are recorded.'
        )
      end
    end

    it 'does not output warning when timestamps are present' do
      stub_presenter_with_timestamp_status('ok')

      stdout, stderr, _status = run_fixture_cli_with_status

      expect(stdout).not_to include('WARNING: Coverage timestamps are missing.')
      expect(stderr).not_to include('WARNING: Coverage timestamps are missing.')
    end

    # Integration tests with real fixture data
    [
      { format: 'table', stream: :stderr, desc: 'table format' },
      { format: 'json', stream: :stderr, desc: 'JSON format' },
    ].each do |tc|
      it "warns about missing timestamps with real fixture data in #{tc[:desc]}" do
        no_timestamp_fixture = File.expand_path('../fixtures/project_no_timestamp', __dir__)
        no_timestamp_resultset = File.join(no_timestamp_fixture, 'coverage', '.resultset.json')

        args = ['--root', no_timestamp_fixture, '--resultset', no_timestamp_resultset]
        args += ['--format', tc[:format]] if tc[:format] != 'table'

        stdout, stderr, _status = run_cli_with_status(*args)
        output = tc[:stream] == :stdout ? stdout : stderr

        expect(output).to include(
          'WARNING: Coverage timestamps are missing.',
          'Time-based staleness checks were skipped.',
          'Files may appear "ok" even if source code is newer than the coverage data.',
          'Check your coverage tool configuration to ensure timestamps are recorded.'
        )
      end
    end
  end

  describe 'validate -i option parsing' do
    %w[validate v].each do |subcommand|
      it "correctly passes -i to the #{subcommand} subcommand" do
        # This confirms that global option parsing (in ConfigParser) does not
        # strip subcommand-specific options like -i.
        _stdout, _stderr, status = run_fixture_full_cli_with_status(subcommand, '-i',
          '->(m) { m.project_totals["lines"]["percentage"] >= 10 }')
        expect(status).to eq(0)
      end
    end
  end
end
