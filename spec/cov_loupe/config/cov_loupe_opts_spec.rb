# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'COV_LOUPE_OPTS Environment Variable' do
  let(:cli) { CovLoupe::CoverageCLI.new }

  around do |example|
    original_value = ENV['COV_LOUPE_OPTS']
    example.run
  ensure
    ENV['COV_LOUPE_OPTS'] = original_value
  end

  describe 'CLI option parsing from environment' do
    it 'parses simple options from COV_LOUPE_OPTS' do
      ENV['COV_LOUPE_OPTS'] = '--error-mode off --format json'
      env_opts = CovLoupe.send(:extract_env_opts)

      swallow_system_exit do
        suppress_io do
          cli.send(:run, env_opts + %w[summary lib/foo.rb])
        end
      end
    rescue CovLoupe::Error
      # Expected to fail due to missing file, but options should be parsed
    ensure
      expect(cli.config.error_mode).to eq(:off)
      expect(cli.config.format).to eq(:json)
    end

    it 'handles quoted options with spaces' do
      test_path = File.join(Dir.tmpdir, 'test path with spaces', 'coverage.json')
      ENV['COV_LOUPE_OPTS'] = "--coverage-file \"#{test_path}\""
      env_opts = CovLoupe.send(:extract_env_opts)

      exit_status = swallow_system_exit do
        suppress_io do
          cli.send(:run, env_opts + %w[--help])
        end
      end

      expect(exit_status).to eq(0) # --help exits cleanly
      expect(cli.config.coverage_file).to eq(test_path)
    end

    it 'rejects setting log-file to stdout from environment' do
      ENV['COV_LOUPE_OPTS'] = '--log-file stdout'
      env_opts = CovLoupe.send(:extract_env_opts)

      expect do
        CovLoupe::ConfigParser.parse(env_opts + %w[summary lib/foo.rb])
      end.to raise_error(CovLoupe::ConfigurationError, /stdout.*not permitted/)
    end

    it 'allows command-line --log-file to override stdout from environment' do
      ENV['COV_LOUPE_OPTS'] = '--log-file stdout'
      env_opts = CovLoupe.send(:extract_env_opts)

      config = CovLoupe::ConfigParser.parse(env_opts + %w[--log-file stderr summary lib/foo.rb])
      expect(config.log_file).to eq('stderr')
    end

    it 'command line arguments override environment options' do
      ENV['COV_LOUPE_OPTS'] = '--error-mode off'
      env_opts = CovLoupe.send(:extract_env_opts)

      begin
        args = env_opts + %w[--error-mode debug summary lib/foo.rb]
        suppress_io { cli.send(:run, args) }
      rescue SystemExit, CovLoupe::Error
        # Expected to fail, but options should be parsed
      end

      # Command line should override environment
      expect(cli.config.error_mode).to eq(:debug)
    end

    it 'handles malformed COV_LOUPE_OPTS gracefully' do
      ENV['COV_LOUPE_OPTS'] = '--option "unclosed quote'

      # Should catch the ConfigurationError and exit cleanly
      _out, _err, status = run_cli_with_status('summary', 'lib/foo.rb')
      expect(status).not_to eq(0)
    end

    [
      { desc: 'returns empty array when COV_LOUPE_OPTS is not set', env_value: nil },
      { desc: 'returns empty array when COV_LOUPE_OPTS is empty', env_value: '' },
    ].each do |test_case|
      it test_case[:desc] do
        ENV['COV_LOUPE_OPTS'] = test_case[:env_value] if test_case[:env_value]
        opts = CovLoupe.send(:extract_env_opts)
        expect(opts).to eq([])
      end
    end
  end

  describe 'CLI mode with COV_LOUPE_OPTS' do
    it 'respects --mode cli from environment variable' do
      ENV['COV_LOUPE_OPTS'] = '--mode cli'

      env_opts = CovLoupe.send(:extract_env_opts)
      full_argv = env_opts + []

      config = CovLoupe::ConfigParser.parse(full_argv)
      expect(config.mode).to eq(:cli)
    end

    it 'raises ConfigurationError for parse errors' do
      ENV['COV_LOUPE_OPTS'] = '--option "unclosed quote'

      # Should raise ConfigurationError instead of silently ignoring
      expect do
        CovLoupe.send(:extract_env_opts)
      end.to raise_error(CovLoupe::ConfigurationError, /Invalid COV_LOUPE_OPTS format/)
    end

    it 'actually runs CLI when --mode cli is in COV_LOUPE_OPTS' do
      ENV['COV_LOUPE_OPTS'] = '--mode cli'

      # Run with --help which should produce help output
      _result, out, err = capture_io do
        swallow_system_exit do
          CovLoupe.run(['--help'])
        end
      end
      output = out + err

      # Verify CLI actually ran by checking for help text
      expect(output).to include('Usage:')
      expect(output).to include('cov-loupe')
    end

    it 'actually runs MCP server mode when --mode mcp is specified' do
      ENV['COV_LOUPE_OPTS'] = ''

      # Provide a minimal JSON-RPC request that the server can handle
      json_request = JSON.generate({
        jsonrpc: '2.0',
        id:      1,
        method:  'initialize',
        params:  {
          protocolVersion: '2024-11-05',
          capabilities:    {},
          clientInfo:      { name: 'test', version: '1.0' },
        },
      })

      allow($stdin).to receive(:gets).and_return(json_request, nil)

      # Capture output to verify MCP server response
      _result, out, err = capture_io { CovLoupe.run(%w[--mode mcp]) }
      output = out + err

      # Verify MCP server ran by checking for JSON-RPC response
      expect(output).to include('"jsonrpc"')
      expect(output).to include('"result"')
    end
  end

  # The error message cannot say whether a bad global option came from COV_LOUPE_OPTS or the
  # command line, so the line after it names COV_LOUPE_OPTS when the error is there.
  describe 'usage errors with COV_LOUPE_OPTS set' do
    def note(opts)
      "The error is in COV_LOUPE_OPTS (#{opts.inspect}), which is read before the command line."
    end

    # Each case: the error, COV_LOUPE_OPTS, and the command line before 'list' (or the whole
    # command line, when it ends with nil).
    [
      ['an invalid option argument', '-f bogus', []],
      ['an attached invalid option argument', '-fbogus', []],
      ['an invalid long-form option argument', '--format bogus', []],
      ['an invalid --opt=value argument', '--format=bogus', []],
      ['an invalid option argument overridden on the command line', '-f bogus', %w[-f json]],
      ['a usage error raised by an option', "-g 'lib/[ab'", []],
      ['an unknown --path-for name', '-p bogus', []],
      ['an invalid --log-file', '--log-file stdout', []],
      ['an invalid --log-file also on the command line', '--log-file stdout', %w[-l stdout]],
      # COV_LOUPE_OPTS is parsed on its own first, so a trailing option there that needs a
      # value is missing it, rather than taking the first command-line argument.
      ['a trailing option, with no command line', '-f', [nil]],
      ['a trailing option, before a command-line option', '-f', %w[-x]],
      ['a trailing option, before a command-line value', '-f', %w[json -x]],
      ['a trailing --log-file, before a command-line value', '--log-file', [nil, 'stdout']],
    ].each do |desc, opts, argv|
      it "names COV_LOUPE_OPTS once, before the help line, for #{desc}" do
        ENV['COV_LOUPE_OPTS'] = opts
        args = argv.first.nil? ? argv.compact : [*argv, 'list']
        _stdout, stderr, status = run_full_cli_with_status(*args)

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(stderr.scan('COV_LOUPE_OPTS (').size).to eq(1)
        expect(stderr.lines.last(2).map(&:chomp))
          .to eq [note(opts), "Run 'cov-loupe --help' for usage information."]
      end
    end

    it 'lets the command line override an invalid --log-file in COV_LOUPE_OPTS' do
      ENV['COV_LOUPE_OPTS'] = '--log-file stdout'
      _stdout, stderr, status = run_fixture_full_cli_with_status('-l', 'stderr', 'list')

      expect(status).to eq(CovLoupe::ExitCodes::SUCCESS)
      expect(stderr).not_to include('COV_LOUPE_OPTS (')
    end

    [
      ['COV_LOUPE_OPTS is unset', nil, %w[-o zzz]],
      ['COV_LOUPE_OPTS is empty', '', %w[-o zzz]],
      ['COV_LOUPE_OPTS is not splittable', "-g 'x", %w[-o zzz]],
      ['an unknown option is on the command line', '-f json', %w[--formt json]],
      ['an invalid value is on the command line', '-f json', %w[-o zzz]],
      ['an invalid value for an option also in COV_LOUPE_OPTS is on the command line',
        '-f json', %w[-f bogus]],
      ['a usage error raised by an option is on the command line', '-f json', ['-g', 'lib/[ab']],
      ['an unknown --path-for name is on the command line', '-f json', %w[-p bogus]],
      ['an invalid --log-file is on the command line', '-f json', %w[--log-file stdout]],
      ['an argument on the command line is not valid UTF-8', '-f json', ["lib/\xFF.rb"]],
      # COV_LOUPE_OPTS fails only validation, which a parse error on the command line precedes.
      ['a parse error is on the command line and --log-file stdout in COV_LOUPE_OPTS',
        '--log-file stdout', %w[-o zzz]],
      ['a usage error raised by an option is on the command line and --log-file stdout in ' \
       'COV_LOUPE_OPTS', '--log-file stdout', ['-g', 'lib/[ab']],
      ['--log-file stdout in COV_LOUPE_OPTS is overridden and a parse error follows',
        '--log-file stdout', %w[-l stderr -o zzz]],
    ].each do |desc, opts, argv|
      it "adds no note when #{desc}" do
        ENV['COV_LOUPE_OPTS'] = opts
        _stdout, stderr, status = run_full_cli_with_status(*argv, 'list')

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(stderr).not_to include('COV_LOUPE_OPTS (')
      end
    end

    # The server is stubbed so that the spec fails rather than waits on stdin.
    it 'names COV_LOUPE_OPTS when it stops the MCP server from starting' do
      allow(CovLoupe::MCPServer).to receive(:new)
      ENV['COV_LOUPE_OPTS'] = "-g 'lib/[ab'"
      _stdout, stderr, status = run_full_cli_with_status('--mode', 'mcp')

      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(stderr).to include(note("-g 'lib/[ab'"))
      expect(CovLoupe::MCPServer).not_to have_received(:new)
    end

    # A subcommand or '--' in COV_LOUPE_OPTS ends the options, as in one parse of both, so the
    # command line's options are not run; the CLI then reports them as misplaced or unknown.
    [
      ['list', %w[-f json], 'Global option(s) must come BEFORE the subcommand'],
      ['list', %w[-m mcp], 'Global option(s) must come BEFORE the subcommand'],
      ['--', %w[-h], "Unknown subcommand: '-h'"],
      ['--', %w[-m mcp], "Unknown subcommand: '-m'"],
      ['-f json --', %w[-v], "Unknown subcommand: '-v'"],
    ].each do |opts, argv, message|
      it "does not parse #{argv.join(' ')} on the command line after #{opts.inspect} in COV_LOUPE_OPTS" do
        allow(CovLoupe::MCPServer).to receive(:new)
        ENV['COV_LOUPE_OPTS'] = opts
        stdout, stderr, status = run_full_cli_with_status(*argv, 'list')

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(stdout).to eq('')
        expect(stderr).to include(message)
        expect(stderr).not_to include('COV_LOUPE_OPTS (')
        expect(CovLoupe::MCPServer).not_to have_received(:new)
      end
    end

    # Options that print and exit must not run while the error's source is worked out: here
    # the bad command-line argument is rejected before COV_LOUPE_OPTS is parsed.
    ['-h', '-v', '-p repo'].each do |opts|
      it "does not run #{opts} from COV_LOUPE_OPTS when a command-line argument is not valid UTF-8" do
        ENV['COV_LOUPE_OPTS'] = opts
        stdout, stderr, status = run_full_cli_with_status("lib/\xFF.rb", 'list')

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(stdout).to eq('')
        expect(stderr).to include('is not valid UTF-8 text')
        expect(stderr).not_to include('COV_LOUPE_OPTS (')
      end
    end

    # Only the global options are checked; later errors, even ones COV_LOUPE_OPTS caused, are not.
    it 'adds no note to an error found after the options are parsed' do
      ENV['COV_LOUPE_OPTS'] = '-c /no/such/coverage.json'
      _stdout, stderr, status = run_full_cli_with_status('list')

      expect(status).to eq(CovLoupe::ExitCodes::ERROR)
      expect(stderr).not_to include('COV_LOUPE_OPTS (')
    end

    # Under a non-UTF-8 locale ENV values arrive as binary; they are shown as text, like the
    # arguments, rather than as escaped bytes.
    it 'shows a non-ASCII COV_LOUPE_OPTS value as text' do
      value = "-g 'café/[ab'"
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('COV_LOUPE_OPTS').and_return(value.b)
      _stdout, stderr, _status = run_fixture_full_cli_with_status('list')

      expect(stderr).to include(note(value))
    end

    # --path-for exists to print only a value, so its error must leave stdout empty.
    it 'reports an unknown --path-for name like other usage errors' do
      ENV['COV_LOUPE_OPTS'] = nil
      stdout, stderr, status = run_full_cli_with_status('-p', 'bogus')

      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(stdout).to eq('')
      expect(stderr).to eq(
        "Error: Unknown resource: 'bogus'. Valid resources: docs, docs-local, repo\n" \
        "Run 'cov-loupe --help' for usage information.\n"
      )
    end
  end

  describe 'tracked globs from COV_LOUPE_OPTS' do
    # COV_LOUPE_OPTS is split with Shellwords, then -g goes through the same brace-aware
    # splitter as on the command line.
    it 'keeps a brace pattern whole' do
      ENV['COV_LOUPE_OPTS'] = "-f json -g 'lib/{foo,bar}.rb'"
      stdout, _stderr, status = run_fixture_full_cli_with_status('list')

      expect(status).to eq(0)
      files = JSON.parse(stdout)['files'].map { |row| row['file'] }
      expect(files).to contain_exactly('lib/foo.rb', 'lib/bar.rb')
    end

    # An unclosed bracket is a usage error even for a per-file command, which ignores -g.
    it 'reports an unclosed bracket as a usage error for every command' do
      ENV['COV_LOUPE_OPTS'] = "-g 'lib/[ab'"
      _stdout, stderr, status = run_fixture_full_cli_with_status('summary', 'lib/foo.rb')

      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(stderr).to include(%q(Unclosed '[' in --tracked-globs value: "lib/[ab"))
    end

    # Shellwords removes an unquoted backslash, so the docs say to quote an escaped comma there.
    [
      ["-g 'a\\,b.rb,c.rb'", ['a\\,b.rb', 'c.rb']],
      ['-g a\\,b.rb,c.rb', %w[a b.rb c.rb]],
    ].each do |opts, globs|
      it "parses #{opts} into #{globs}" do
        # Off Windows, where a backslash would be a path separator rather than an escape.
        allow(CovLoupe).to receive(:windows?).and_return(false)
        ENV['COV_LOUPE_OPTS'] = opts

        expect(CovLoupe::ConfigParser.parse(CovLoupe.send(:extract_env_opts)).tracked_globs).to eq(globs)
      end
    end
  end

  describe 'integration with actual CLI usage' do
    it 'works end-to-end with --coverage-file option' do
      test_coverage_file = File.join(Dir.tmpdir, 'test_coverage', 'coverage.json')
      ENV['COV_LOUPE_OPTS'] = "--coverage-file #{test_coverage_file} --format json"
      env_opts = CovLoupe.send(:extract_env_opts)

      swallow_system_exit do
        suppress_io { cli.send(:run, env_opts + ['--help']) }
      end

      expect(cli.config.coverage_file).to eq(test_coverage_file)
      expect(cli.config.format).to eq(:json)
    end
  end
end
