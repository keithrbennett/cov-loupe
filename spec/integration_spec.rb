# frozen_string_literal: true

require 'spec_helper'

# Timeout for MCP server operations (increased for JRuby compatibility)
MCP_TIMEOUT = 5

RSpec.describe 'SimpleCov MCP Integration Tests' do
  include CLITestHelpers

  let(:project_root) { (FIXTURES_DIR / 'project1').to_s }
  let(:coverage_dir) { File.join(project_root, 'coverage') }
  let(:resultset_path) { File.join(coverage_dir, '.resultset.json') }

  describe 'End-to-End Coverage Model Functionality' do
    it 'loads fixture coverage and surfaces core stats across APIs' do
      model = CovLoupe::CoverageModel.new(root: project_root, resultset: coverage_dir)

      aggregate_failures 'Model stats verification' do
        list_result = model.list
        files = list_result['files']
        expect(files.length).to eq(2)

        %w[skipped_files missing_tracked_files newer_files deleted_files].each do |key|
          expect(list_result[key]).to be_a(Array), "Expected list_result['#{key}'] to be an Array"
        end

        files_by_name = files.to_h { |f| [File.basename(f['file']), f] }

        foo = files_by_name.fetch('foo.rb')
        bar = files_by_name.fetch('bar.rb')
        expect(foo['percent_covered']).to be_within(0.01).of(66.67)
        expect(bar['percent_covered']).to be_within(0.01).of(33.33)

        raw = model.raw_for('lib/foo.rb')
        expect(raw['lines']).to eq([nil, nil, 1, 0, nil, 2])

        summary = model.summary_for('lib/foo.rb')
        expect(summary['summary']).to include('covered' => 2, 'total' => 3)

        uncovered = model.uncovered_for('lib/foo.rb')
        expect(uncovered['uncovered']).to eq([4])

        detailed = model.detailed_for('lib/foo.rb')
        expect(detailed['lines']).to include({ 'line' => 4, 'hits' => 0, 'covered' => false })

        table = model.format_table
        expect(table).to include('lib/foo.rb', 'lib/bar.rb', '66.67', '33.33')
        data_lines = table.split("\n").select { |line| line.include?('lib/') }
        expect(data_lines.first).to include('lib/foo.rb') # Highest coverage first (descending default)
        expect(data_lines.last).to include('lib/bar.rb')
      end
    end
  end

  describe 'CLI Integration with Real Coverage Data' do
    def run_cli_command(*args)
      output, _err, status = run_fixture_cli_with_status(*args)
      expect(status).to eq(0)
      output
    end

    it 'executes all major CLI commands without errors' do
      aggregate_failures 'CLI commands' do
        # Test list command
        list_output = run_cli_command('list')
        expect(list_output).to include('lib/foo.rb', 'lib/bar.rb', '66.67', '33.33')
        # Select only table rows (lines starting with │) that contain file paths
        data_lines = list_output.lines.select do |line|
          line.start_with?('│') && line.include?('lib/')
        end
        expect(data_lines.first).to include('lib/foo.rb')
        expect(data_lines.last).to include('lib/bar.rb')

        # Test summary command
        summary_output = run_cli_command('summary', 'lib/foo.rb')
        expect(summary_output).to include('│', '66.67%', '2', '3')

        # Test JSON output
        json_output = run_cli_command('--format', 'json', 'summary', 'lib/foo.rb')
        json_data = JSON.parse(json_output)
        expect(json_data).to include('file', 'summary')
        expect(json_data['summary']).to include('covered' => 2, 'total' => 3)
      end
    end

    it 'handles different output formats correctly' do
      aggregate_failures 'Output formats' do
        # Test uncovered command with different outputs
        uncovered_output = run_cli_command('uncovered', 'lib/foo.rb')
        expect(uncovered_output).to include('│')

        # Test detailed command
        detailed_output = run_cli_command('detailed', 'lib/foo.rb')
        expect(detailed_output).to include('Line', 'Hits', 'Covered')
      end
    end
  end

  describe 'MCP Tool Integration with Real Data' do
    let(:server_context) { null_server_context }

    before do
      setup_mcp_response_stub
    end

    it 'executes all MCP tools with real coverage data' do
      aggregate_failures 'MCP tools' do
        # Test coverage summary tool
        summary_response = CovLoupe::Tools::CoverageSummaryTool.call(
          path: 'lib/foo.rb',
          root: project_root,
          resultset: coverage_dir,
          server_context: server_context
        )

        data, _item = expect_mcp_text_json(summary_response, expected_keys: %w[file summary])
        expect(data['summary']).to include('covered' => 2, 'total' => 3)

        # Test raw coverage tool
        raw_response = CovLoupe::Tools::CoverageRawTool.call(
          path: 'lib/foo.rb',
          root: project_root,
          resultset: coverage_dir,
          server_context: server_context
        )

        raw_data, _raw_item = expect_mcp_text_json(raw_response, expected_keys: %w[file lines])
        expect(raw_data['lines']).to eq([nil, nil, 1, 0, nil, 2])

        # Test all files tool
        list_response = CovLoupe::Tools::ListTool.call(
          root: project_root,
          resultset: coverage_dir,
          server_context: server_context
        )

        all_data, = expect_mcp_text_json(list_response, expected_keys: %w[files counts])
        expect(all_data['files'].length).to eq(2)
        expect(all_data['counts']['total']).to eq(2)
      end
    end

    it 'provides consistent data across different tools' do
      aggregate_failures 'Tool consistency' do
        summary_data, = expect_mcp_text_json(
          CovLoupe::Tools::CoverageSummaryTool.call(
            path: 'lib/foo.rb',
            root: project_root,
            resultset: coverage_dir,
            server_context: server_context
          )
        )

        detailed_data, = expect_mcp_text_json(
          CovLoupe::Tools::CoverageDetailedTool.call(
            path: 'lib/foo.rb',
            root: project_root,
            resultset: coverage_dir,
            server_context: server_context
          )
        )

        expect(summary_data['summary']).to include('covered' => 2, 'total' => 3)
        expect(detailed_data['summary']).to include('covered' => 2, 'total' => 3)
        expect(detailed_data['lines'].count { |l| l['covered'] }).to eq(2)
      end
    end
  end

  describe 'Error Handling Integration' do
    it 'handles missing files gracefully' do
      model = CovLoupe::CoverageModel.new(root: project_root, resultset: coverage_dir)

      expect do
        model.summary_for('lib/nonexistent.rb')
      end.to raise_error(CovLoupe::FileError, /No coverage entry found/)
    end

    it 'handles invalid resultset paths gracefully' do
      expect do
        CovLoupe::CoverageModel.new(root: project_root, resultset: '/nonexistent/path')
      end.to raise_error(CovLoupe::ResultsetNotFoundError, /Specified resultset not found/)
    end

    it 'provides helpful CLI error messages' do
      _output, error, status = run_fixture_cli_with_status('summary', 'lib/nonexistent.rb')

      expect(status).to eq(1)
      expect(error).to include('File error:', 'No coverage entry found')
    end
  end

  describe 'Multi-File Scenarios' do
    let(:model) { CovLoupe::CoverageModel.new(root: project_root, resultset: coverage_dir) }

    it 'handles mixed coverage levels and project reports' do
      aggregate_failures do
        # Verify range of coverage
        files = model.list['files']
        coverages = files.map { |f| f['percent_covered'] }

        expect(coverages.min).to be < 50
        expect(coverages.max).to be > 50
        expect(coverages).to include(a_value_within(0.1).of(33.33))
        expect(coverages).to include(a_value_within(0.1).of(66.67))

        # Check table format
        table = model.format_table
        expect(table).to match(/lib\/bar\.rb.*33\.33/)
        expect(table).to match(/lib\/foo\.rb.*66\.67/)
        expect(table).to include('Files: total 2')
      end
    end
  end

  describe 'MCP Server Protocol Integration', :slow do
    # spec/ is one level deep, so ../.. goes up to repo root
    let(:repo_root) { File.expand_path('..', __dir__) }
    let(:exe_path) { File.join(repo_root, 'exe', 'cov-loupe') }
    let(:lib_path) { File.join(repo_root, 'lib') }

    let(:default_env) do
      {
        'RUBY_LIB' => lib_path,
        'COV_LOUPE_OPTS' => "--mode mcp --root #{project_root} --resultset #{coverage_dir} --log-file /dev/null"
      }
    end

    def runner_args(env: default_env, timeout: 5)
      { env: env, lib_path: lib_path, exe_path: exe_path, timeout: timeout }
    end

    def run_mcp_json(request_hash, env: default_env, timeout: MCP_TIMEOUT)
      Spec::Support::McpRunner.call_json(
        request_hash, **runner_args(env: env, timeout: timeout)
      )
    end

    def jsonrpc_request(id, method, params = nil)
      request = { jsonrpc: '2.0', id: id, method: method }
      request[:params] = params if params
      request
    end

    def jsonrpc_call(id, method, params = nil)
      parse_jsonrpc(run_mcp_json(jsonrpc_request(id, method, params))[:stdout])
    end

    def jsonrpc_tool_call(id, name, arguments = {})
      jsonrpc_call(id, 'tools/call', { name: name, arguments: arguments })
    end

    def parse_jsonrpc(output)
      lines = output.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        .lines
        .map(&:strip)
        .reject(&:empty?)

      lines.each do |line|
        parsed = JSON.parse(line)
        return parsed if parsed['jsonrpc'] == '2.0'
      rescue JSON::ParserError
        # Continue searching
      end
      raise "No valid JSON-RPC response found. Output: #{output}"
    end

    def expect_jsonrpc_result(response, id)
      expect(response).to include('jsonrpc' => '2.0', 'id' => id)
      expect(response).to have_key('result')
      response['result']
    end

    def expect_jsonrpc_error(response, id)
      expect(response).to include('jsonrpc' => '2.0', 'id' => id)
      if response['error']
        expect(response['error']).to have_key('message')
      elsif response['result']
        content = response['result']['content']
        text = content.first['text']
        expect(text.downcase).to match(/error|not found|required/)
      else
        raise 'Expected error or result with error message'
      end
    end

    it 'starts MCP server and handles tool listing' do
      aggregate_failures do
        # Start server check
        result = run_mcp_json(jsonrpc_request(1, 'tools/list'))
        expect(result[:stderr]).not_to match(/NameError|uninitialized constant|OptionParser/)

        response = parse_jsonrpc(result[:stdout])
        expect_jsonrpc_result(response, 1)

        tools = response['result']['tools']
        expect(tools).to be_an(Array)
        expect(tools.map { |t| t['name'] }).to include(
          'list_tool', 'coverage_summary_tool', 'coverage_raw_tool',
          'uncovered_lines_tool', 'coverage_detailed_tool', 'help_tool'
        )
      end
    end

    it 'executes coverage tools via JSON-RPC' do
      aggregate_failures do
        # coverage_summary_tool
        resp1 = jsonrpc_tool_call(
          3,
          'coverage_summary_tool',
          { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir }
        )
        content = expect_jsonrpc_result(resp1, 3)['content']
        data = JSON.parse(content.first['text'])
        expect(data['summary']).to include('covered' => 2, 'total' => 3)

        # list_tool
        resp2 = jsonrpc_tool_call(4, 'list_tool', { root: project_root, resultset: coverage_dir })
        content = expect_jsonrpc_result(resp2, 4)['content']
        data = JSON.parse(content.first['text'])
        expect(data['files'].length).to eq(2)

        # uncovered_lines_tool
        resp3 = jsonrpc_tool_call(
          5,
          'uncovered_lines_tool',
          { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir }
        )
        content = expect_jsonrpc_result(resp3, 5)['content']
        data = JSON.parse(content.first['text'])
        expect(data['uncovered']).to eq([4])
      end
    end

    it 'executes utility tools via JSON-RPC' do
      aggregate_failures do
        # help_tool
        resp1 = jsonrpc_tool_call(6, 'help_tool')
        content = expect_jsonrpc_result(resp1, 6)['content']
        help_data = JSON.parse(content.first['text'])
        expect(help_data['tools'].map { |t| t['tool'] }).to include('coverage_summary_tool')

        # version_tool
        resp2 = jsonrpc_tool_call(7, 'version_tool')
        content = expect_jsonrpc_result(resp2, 7)['content']
        expect(content.first['text']).to match(/CovLoupe version: \d+\.\d+/)
      end
    end

    it 'executes validate_tool via JSON-RPC' do
      resp = jsonrpc_tool_call(
        80,
        'validate_tool',
        {
          code: '->(m) { true }',
          root: project_root,
          resultset: coverage_dir
        }
      )
      content = expect_jsonrpc_result(resp, 80)['content']
      expect(JSON.parse(content.first['text'])).to include('result' => true)
    end

    it 'handles error cases' do
      aggregate_failures do
        [
          {
            id: 8,
            name: 'coverage_summary_tool',
            arguments: {
              path: 'nonexistent.rb',
              root: project_root,
              resultset: coverage_dir
            }
          },
          { id: 201, name: 'coverage_summary_tool', arguments: {} },
          { id: 200, name: 'nonexistent_tool', arguments: {} }
        ].each do |request|
          response = jsonrpc_tool_call(request[:id], request[:name], request[:arguments])
          expect_jsonrpc_error(response, request[:id])
        end
      end
    end

    it 'handles malformed or partial inputs gracefully' do
      env = { 'RUBY_LIB' => lib_path }

      # Malformed JSON
      res1 = Spec::Support::McpRunner.call(
        input: "{'jsonrpc': '2.0', 'id': 999, 'method': 'invalid'}",
        **runner_args(env: env)
      )
      expect(res1[:stderr]).not_to include('NameError', 'uninitialized constant')

      # Partial JSON
      res2 = Spec::Support::McpRunner.call(
        input: '{"jsonrpc": "2.0", "id": 300, "method":',
        **runner_args(env: env)
      )

      expect(res2[:stderr]).not_to include('uninitialized constant')

      # Empty input
      res3 = Spec::Support::McpRunner.call(input: '', **runner_args(env: env))
      expect(res3[:stderr]).not_to include('NameError')
    end

    it 'handles logging configuration' do
      # Respects --log-file

      req = jsonrpc_request(10, 'tools/call', { name: 'version_tool', arguments: {} })
      res = run_mcp_json(req, env: default_env.merge('COV_LOUPE_OPTS' =>
        "--mode mcp --root #{project_root} --resultset #{coverage_dir} --log-file stderr"))
      expect_jsonrpc_result(parse_jsonrpc(res[:stdout]), 10)

      # Prohibits stdout logging
      res_err = Spec::Support::McpRunner.call(
        input: nil,
        **runner_args(env:
          { 'RUBY_LIB' => lib_path, 'COV_LOUPE_OPTS' => '--mode mcp --log-file stdout' })
      )

      expect(res_err[:stdout] + res_err[:stderr]).to include('stdout', 'not permitted')
      expect(res_err[:status].exitstatus).not_to eq(0)
    end

    it 'handles multiple sequential requests' do
      requests = [
        jsonrpc_request(100, 'tools/list'),
        jsonrpc_request(101, 'tools/call', { name: 'version_tool', arguments: {} })
      ]

      result = Spec::Support::McpRunner.call_json_stream(requests, **runner_args)
      output = result[:stdout].to_s.encode('UTF-8', invalid: :replace, undef: :replace,
        replace: '')
      ids = output.lines.map do |line|
        JSON.parse(line)['id']
      rescue
        nil
      end.compact
      expect(ids).to include(100).or include(101)
    end
  end
end
