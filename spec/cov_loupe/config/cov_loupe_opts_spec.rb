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
      test_path = File.join(Dir.tmpdir, 'test path with spaces', '.resultset.json')
      ENV['COV_LOUPE_OPTS'] = "--resultset \"#{test_path}\""
      env_opts = CovLoupe.send(:extract_env_opts)

      exit_status = swallow_system_exit do
        suppress_io do
          cli.send(:run, env_opts + %w[--help])
        end
      end

      expect(exit_status).to eq(0) # --help exits cleanly
      expect(cli.config.resultset).to eq(test_path)
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

  describe 'integration with actual CLI usage' do
    it 'works end-to-end with --resultset option' do
      test_resultset = File.join(Dir.tmpdir, 'test_coverage', '.resultset.json')
      ENV['COV_LOUPE_OPTS'] = "--resultset #{test_resultset} --format json"
      env_opts = CovLoupe.send(:extract_env_opts)

      swallow_system_exit do
        suppress_io { cli.send(:run, env_opts + ['--help']) }
      end

      expect(cli.config.resultset).to eq(test_resultset)
      expect(cli.config.format).to eq(:json)
    end
  end
end
