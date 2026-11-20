# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'

# Options after the subcommand (parsed by CovLoupe.run; see ConfigParser#parse_subcommand_options).
RSpec.describe CovLoupe::CoverageCLI do
  # Each subcommand with the positional arguments it needs.
  subcommand_args = {
    'list' => [], 'totals' => [], 'summary' => ['lib/foo.rb'], 'raw' => ['lib/foo.rb'],
    'uncovered' => ['lib/foo.rb'], 'detailed' => ['lib/foo.rb'],
    'validate' => ['-i', '->(m) { true }']
  }
  non_validate = subcommand_args.keys - ['validate'] + (CovLoupe::SUBCOMMAND_ABBREVIATIONS.keys - ['v'])

  # Runs argv through CovLoupe.run with the CLI stubbed; returns what the CLI was given.
  def parsed(*argv)
    captured = nil
    cli = instance_double(described_class)
    allow(cli).to receive(:run) do |args, config:, inline_code:|
      captured = { args: args, config: config, inline_code: inline_code }
    end
    allow(described_class).to receive(:new).and_return(cli)
    CovLoupe.run(argv)
    captured
  end

  describe 'options after the subcommand' do
    [
      [%w[-c cov.json], :coverage_file, 'cov.json'],
      [%w[--coverage-file=cov.json], :coverage_file, 'cov.json'],
      [%w[-R proj], :root, 'proj'],
      [%w[-f json], :format, :json],
      [%w[--format=yaml], :format, :yaml],
      [%w[--form json], :format, :json], # abbreviated long options work, as before the subcommand
      [%w[-o a], :sort_order, :ascending],
      [%w[-s full], :source_mode, :full],
      [%w[-n 3], :source_context, 3],
      [%w[-C false], :color, false],
      [%w[-S true], :raise_on_stale, true],
      [%w[-g lib/**/*.rb], :file_globs, ['lib/**/*.rb']],
      [%w[-l off], :log_file, 'off'],
      [%w[-e debug], :error_mode, :debug],
      [%w[-O ascii], :output_chars, :ascii],
    ].each do |option, attr, expected|
      subcommand_args.each do |cmd, cmd_args|
        it "applies #{option.join(' ')} after #{cmd}" do
          result = parsed(cmd, *cmd_args, *option)
          expect(result[:config].public_send(attr)).to eq(expected)
        end
      end
    end

    it 'keeps the positional arguments, in order, around the options' do
      result = parsed('summary', '-f', 'json', 'lib/foo.rb', '-o', 'a')
      expect(result[:args]).to eq(%w[summary lib/foo.rb])
    end

    it 'gives the command line precedence: COV_LOUPE_OPTS, then before, then after the subcommand' do
      ENV['COV_LOUPE_OPTS'] = '-f json'
      expect(parsed('totals', '-f', 'yaml')[:config].format).to eq(:yaml)
      expect(parsed('-f', 'yaml', 'totals', '-f', 'pretty_json')[:config].format).to eq(:pretty_json)
    end

    it "passes the arguments after '--' as positional arguments" do
      expect(parsed('summary', '--', '-odd.rb')[:args]).to eq(%w[summary -odd.rb])
    end

    it 'resolves an abbreviated subcommand before parsing its options' do
      result = parsed('s', 'lib/foo.rb', '-f', 'json')
      expect(result[:args]).to eq(%w[s lib/foo.rb])
      expect(result[:config].format).to eq(:json)
    end

    it 'runs a real command with options after it' do
      data = JSON.parse(run_fixture_cli_output('summary', 'lib/foo.rb', '--format', 'json'))
      expect(data).to include('file', 'percentage')
    end
  end

  [[%w[-n -1], 'Context lines cannot be negative'], [['-g', 'lib/[ab'], 'lib/[ab']].each do |option, message|
    it "rejects the invalid value in `#{option.join(' ')}` after the subcommand" do
      _out, err, status = run_fixture_cli_with_status('list', *option)
      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(err).to include(message)
    end
  end

  describe 'options allowed only before the subcommand' do
    [%w[--vers], %w[--mod mcp], %w[--allow]].each do |option|
      it "names abbreviated #{option.first} as allowed only before the subcommand" do
        _out, err, status = run_fixture_cli_with_status('list', *option)
        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(err).to include("#{option.first} must come before the subcommand")
      end
    end

    [
      %w[-h], %w[--help], %w[-v], %w[--version], %w[-p repo], %w[--path-for=repo], %w[-m mcp],
      %w[--mode=mcp], %w[--allow-code-predicates], %w[--no-allow-code-predicates]
    ].each do |option|
      subcommand_args.each do |cmd, cmd_args|
        it "rejects #{option.join(' ')} after #{cmd}" do
          allow(CovLoupe::MCPServer).to receive(:new)
          out, err, status = run_fixture_cli_with_status(cmd, *cmd_args, *option)

          expect(status).to eq(CovLoupe::ExitCodes::USAGE)
          expect(out).to eq('')
          flag = option.first.split('=').first
          expect(err).to include("#{flag} must come before the subcommand, not after '#{cmd}'")
          expect(CovLoupe::MCPServer).not_to have_received(:new)
        end
      end
    end
  end

  # A rule allowing `cov-loupe <subcommand>` for any subcommand but validate must not let a
  # command run Ruby. The code would create a marker file; its absence proves it did not run.
  describe 'inline code with subcommands other than validate' do
    let(:dir) { Dir.mktmpdir }
    let(:marker) { File.join(dir, 'ran') }
    let(:code) { "->(m) { File.write(#{marker.inspect}, 'x'); true }" }

    after { FileUtils.rm_rf(dir) }

    # Each spelling, with CODE standing for the code.
    spellings = [%w[-i CODE], %w[-iCODE], %w[--inline CODE], %w[--inline=CODE], %w[--in CODE]]
    cases = non_validate.product(spellings).map do |cmd, spelling|
      [cmd, subcommand_args.fetch(CovLoupe.subcommand_for(cmd)), spelling]
    end
    cases.each do |cmd, cmd_args, spelling|
      it "rejects `#{spelling.join(' ')}` after #{cmd} without running the code" do
        option = spelling.map { |arg| arg.sub('CODE', code) }
        _out, _err, status = run_fixture_cli_with_status(cmd, *cmd_args, *option)

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(File.exist?(marker)).to be(false)
      end
    end

    it 'does not accept -i from COV_LOUPE_OPTS' do
      ENV['COV_LOUPE_OPTS'] = "-i #{code.inspect}"
      _out, err, status = run_fixture_cli_with_status('validate')

      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(err).to include('COV_LOUPE_OPTS')
      expect(File.exist?(marker)).to be(false)
    end

    it 'runs the code with validate (positive control)' do
      _out, _err, status = run_fixture_cli_with_status('validate', '-i', code)
      expect(status).to eq(CovLoupe::ExitCodes::SUCCESS)
      expect(File.exist?(marker)).to be(true)
    end
  end

  describe 'validate' do
    it 'passes the inline code to the CLI, with v as the abbreviation' do
      expect(parsed('v', '-i', '->(m) { true }')[:inline_code]).to eq('->(m) { true }')
    end

    [%w[-i CODE], %w[-iCODE], %w[--inline CODE], %w[--inline=CODE]].each do |spelling|
      it "passes the code given as `#{spelling.join(' ')}`" do
        option = spelling.map { |arg| arg.sub('CODE', '->(m) { true }') }
        expect(parsed('validate', *option)[:inline_code]).to eq('->(m) { true }')
      end
    end

    it 'passes -i=CODE as the code =CODE, as OptionParser does for any short option' do
      expect(parsed('validate', '-i=x')[:inline_code]).to eq('=x')
    end

    it 'uses the last -i when it is given twice' do
      expect(parsed('validate', '-i', 'first', '-i', 'second')[:inline_code]).to eq('second')
    end

    it 'takes the argument after -i as the code, even -- or an option' do
      expect(parsed('validate', '-i', '--')[:inline_code]).to eq('--')
      expect(parsed('validate', '-i', '-R', '.')[:inline_code]).to eq('-R')
    end

    it 'rejects a policy file, or any other argument, with -i' do
      _out, err, status = run_fixture_cli_with_status('validate', 'policy.rb', '-i', '->(m) { true }')
      expect(status).to eq(CovLoupe::ExitCodes::USAGE)
      expect(err).to include("Unexpected argument(s) for 'validate': policy.rb")
    end

    [['-i'], ['-i', ''], ['--inline='], ['--in'], ['--inl=']].each do |option|
      it "shows the usage synopsis, without an Error: prefix, for #{option.inspect}" do
        _out, err, status = run_fixture_cli_with_status('validate', *option)
        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(err).to start_with("Usage: cov-loupe validate -i <code>\n")
      end
    end

    it "accepts a policy file after '--'" do
      Dir.mktmpdir do |dir|
        policy = File.join(dir, 'policy.rb')
        File.write(policy, "->(m) { true }\n")
        _out, _err, status = run_fixture_cli_with_status('validate', '--', policy)
        expect(status).to eq(CovLoupe::ExitCodes::SUCCESS)
      end
    end
  end

  describe 'MCP mode' do
    [
      [%w[-m mcp list], nil],
      [%w[-m mcp bogus], nil],
      [%w[list], '-m mcp'],
    ].each do |argv, opts|
      it "rejects #{argv.inspect}#{" with COV_LOUPE_OPTS=#{opts.inspect}" if opts}" do
        ENV['COV_LOUPE_OPTS'] = opts if opts
        allow(CovLoupe::MCPServer).to receive(:new)
        _out, err, status = run_cli_with_status(*argv)

        expect(status).to eq(CovLoupe::ExitCodes::USAGE)
        expect(err).to include('MCP mode takes no subcommand or arguments')
        expect(CovLoupe::MCPServer).not_to have_received(:new)
      end
    end
  end

  it 'runs in CLI mode with -m cli before the subcommand when COV_LOUPE_OPTS selects MCP' do
    ENV['COV_LOUPE_OPTS'] = '-m mcp'
    expect(parsed('-m', 'cli', 'list')[:args]).to eq(%w[list])
  end

  it 'does not suggest a subcommand for an invalid option after one' do
    _out, err, status = run_fixture_cli_with_status('list', '--summary')
    expect(status).to eq(CovLoupe::ExitCodes::USAGE)
    expect(err).to include('invalid option: --summary')
    expect(err).not_to include('Did you mean')
  end

  it "rejects '--' before the subcommand" do
    _out, err, status = run_fixture_cli_with_status('--', 'list')
    expect(status).to eq(CovLoupe::ExitCodes::USAGE)
    expect(err).to include("'--' is allowed only after a subcommand")
  end

  it "accepts '--' as an option's value before the subcommand" do
    expect(parsed('-g', '--', 'list')[:args]).to eq(%w[list])
  end

  it 'leaves an unknown subcommand, and the options after it, to the CLI' do
    expect(parsed('bogus', '-f', 'json')[:args]).to eq(%w[bogus -f json])
  end

  # handle_executable_flags runs only in the executable, so these run it as a process.
  describe 'exe/cov-loupe version shortcut' do
    let(:exe) { File.expand_path('../../../exe/cov-loupe', __dir__) }

    def run_exe(*args)
      Open3.capture3({ 'COV_LOUPE_OPTS' => nil }, RbConfig.ruby, exe, *args)
    end

    it 'prints the version for a first -v' do
      out, _err, status = run_exe('-v')
      expect(status.exitstatus).to eq(0)
      expect(out.strip).to eq(CovLoupe::VERSION)
    end

    it "does not print the version for a -v after '--'" do
      out, _err, _status = run_exe('summary', '--', '-v')
      expect(out).not_to include(CovLoupe::VERSION)
    end
  end
end
