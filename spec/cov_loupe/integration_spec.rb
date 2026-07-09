# frozen_string_literal: true

require 'spec_helper'

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
        expect(foo['percentage']).to be_within(0.01).of(66.67)
        expect(bar['percentage']).to be_within(0.01).of(33.33)

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
        [
          {
            desc:         'list command',
            args:         ['list'],
            expectations: ->(output) {
              expect(output).to include('lib/foo.rb', 'lib/bar.rb', '66.67', '33.33')
              data_lines = output.lines.select { |l| l.start_with?('│') && l.include?('lib/') }
              expect(data_lines.first).to include('lib/foo.rb')
              expect(data_lines.last).to include('lib/bar.rb')
            },
          },
          {
            desc:         'summary command',
            args:         ['summary', 'lib/foo.rb'],
            expectations: ->(output) {
              expect(output).to include('│', '66.67%', '2', '3')
            },
          },
          {
            desc:         'JSON output',
            args:         ['--format', 'json', 'summary', 'lib/foo.rb'],
            expectations: ->(output) {
              json_data = JSON.parse(output)
              expect(json_data).to include('file', 'summary')
              expect(json_data['summary']).to include('covered' => 2, 'total' => 3)
            },
          },
        ].each do |tc|
          output = run_cli_command(*tc[:args])
          tc[:expectations].call(output)
        end
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
        [
          {
            tool:          CovLoupe::Tools::FileCoverageSummaryTool,
            args:          { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir },
            expected_keys: %w[file summary],
            check:         ->(data) { expect(data['summary']).to include('covered' => 2, 'total' => 3) },
          },
          {
            tool:          CovLoupe::Tools::FileCoverageRawTool,
            args:          { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir },
            expected_keys: %w[file lines],
            check:         ->(data) { expect(data['lines']).to eq([nil, nil, 1, 0, nil, 2]) },
          },
          {
            tool:          CovLoupe::Tools::ProjectCoverageTool,
            args:          { root: project_root, resultset: coverage_dir },
            expected_keys: %w[files counts],
            check:         ->(data) {
              expect(data['files'].length).to eq(2)
              expect(data['counts']['total']).to eq(2)
            },
          },
          {
            tool:          CovLoupe::Tools::ProjectCoverageTool,
            args:          { root: project_root, resultset: coverage_dir, format: 'table' },
            expected_keys: [],
            check:         ->(text) { expect(text).to include('lib/foo.rb') },
            is_text:       true,
          },
        ].each do |tc|
          response = tc[:tool].call(**tc[:args], server_context: server_context)
          if tc[:is_text]
            text = response.content.first['text']
            tc[:check].call(text)
          else
            data, = expect_mcp_text_json(response, expected_keys: tc[:expected_keys])
            tc[:check].call(data)
          end
        end
      end
    end

    it 'provides consistent data across different tools' do
      aggregate_failures 'Tool consistency' do
        summary_data, = expect_mcp_text_json(
          CovLoupe::Tools::FileCoverageSummaryTool.call(
            path:           'lib/foo.rb',
            root:           project_root,
            resultset:      coverage_dir,
            server_context: server_context
          )
        )

        detailed_data, = expect_mcp_text_json(
          CovLoupe::Tools::FileCoverageDetailedTool.call(
            path:           'lib/foo.rb',
            root:           project_root,
            resultset:      coverage_dir,
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
        coverages = files.map { |f| f['percentage'] }

        expect(coverages.min).to be < 50
        expect(coverages.max).to be > 50
        expect(coverages).to include(a_value_within(0.1).of(33.33))
        expect(coverages).to include(a_value_within(0.1).of(66.67))

        # Check table format
        table = model.format_table
        expect(table).to match(%r{lib/bar\.rb.*33\.33})
        expect(table).to match(%r{lib/foo\.rb.*66\.67})
        expect(table).to include('Files: total 2')
      end
    end
  end

  describe 'MCP Server Protocol Integration', :slow do
    # __dir__ is spec/cov_loupe, so ../.. goes up to repo root
    let(:repo_root) { File.expand_path('../..', __dir__) }
    let(:exe_path) { File.join(repo_root, 'exe', 'cov-loupe') }
    let(:lib_path) { File.join(repo_root, 'lib') }

    let(:default_env) do
      {
        'RUBY_LIB'       => lib_path,
        'COV_LOUPE_OPTS' => "--mode mcp --root #{project_root} --resultset #{coverage_dir} " \
                            '--log-file /dev/null',
      }
    end

    def runner_args(env: default_env, timeout: INTEGRATION_TIMEOUT)
      { env: env, lib_path: lib_path, exe_path: exe_path, timeout: timeout }
    end

    def run_mcp_json(request_hash, env: default_env, timeout: INTEGRATION_TIMEOUT)
      Spec::Support::McpRunner.call_json(
        request_hash, **runner_args(env: env, timeout: timeout)
      )
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
          'project_coverage', 'file_coverage_summary', 'file_coverage_raw',
          'file_uncovered_lines', 'file_coverage_detailed', 'help'
        )
      end
    end

    it 'executes coverage tools via JSON-RPC' do
      aggregate_failures do
        [
          {
            id:    3,
            name:  'file_coverage_summary',
            args:  { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir },
            check: ->(data) { expect(data['summary']).to include('covered' => 2, 'total' => 3) },
          },
          {
            id:    4,
            name:  'project_coverage',
            args:  { root: project_root, resultset: coverage_dir },
            check: ->(data) { expect(data['files'].length).to eq(2) },
          },
          {
            id:    5,
            name:  'file_uncovered_lines',
            args:  { path: 'lib/foo.rb', root: project_root, resultset: coverage_dir },
            check: ->(data) { expect(data['uncovered']).to eq([4]) },
          },
        ].each do |tc|
          resp = jsonrpc_tool_call(tc[:id], tc[:name], tc[:args])
          result = expect_jsonrpc_result(resp, tc[:id])
          expect(result['isError']).to be(false)
          content = result['content']
          data = JSON.parse(content.first['text'])
          tc[:check].call(data)
        end
      end
    end

    it 'executes utility tools via JSON-RPC' do
      aggregate_failures do
        [
          {
            id:    6,
            name:  'help',
            check: ->(data) {
              tools = data['tools'].map { |t| t['tool'] }
              expect(tools).to include('file_coverage_summary')
            },
          },
          {
            id:    7,
            name:  'version',
            check: ->(text) { expect(text).to match(/CovLoupe version: \d+\.\d+/) },
          },
        ].each do |tc|
          resp = jsonrpc_tool_call(tc[:id], tc[:name])
          result = expect_jsonrpc_result(resp, tc[:id])
          expect(result['isError']).to be(false)
          content = result['content']
          # version returns plain text, help returns JSON text
          if tc[:name] == 'help'
            tc[:check].call(JSON.parse(content.first['text']))
          else
            tc[:check].call(content.first['text'])
          end
        end
      end
    end

    it 'executes project_validate via JSON-RPC' do
      resp = jsonrpc_tool_call(
        80,
        'project_validate',
        {
          code:      '->(m) { true }',
          root:      project_root,
          resultset: coverage_dir,
        }
      )
      result = expect_jsonrpc_result(resp, 80)
      expect(result['isError']).to be(false)
      content = result['content']
      expect(JSON.parse(content.first['text'])).to include('result' => true)
    end

    it 'handles error cases' do
      # Tool-execution failures: project-scope and file-scope tools return a
      # tools/call result with isError: true (tool-result-level error signaling).
      aggregate_failures do
        file_error_resp = jsonrpc_tool_call(
          8,
          'file_coverage_summary',
          {
            path:      'nonexistent.rb',
            root:      project_root,
            resultset: coverage_dir,
          }
        )
        expect_jsonrpc_tool_error(file_error_resp, 8)

        project_scope_error_resp = jsonrpc_tool_call(
          11,
          'project_coverage_totals',
          {
            root:      project_root,
            resultset: File.join(coverage_dir, 'nonexistent.resultset.json'),
          }
        )
        expect_jsonrpc_tool_error(project_scope_error_resp, 11)

        project_error_resp = jsonrpc_tool_call(
          9,
          'project_validate',
          {
            code:      'this is not valid ruby {',
            root:      project_root,
            resultset: coverage_dir,
          }
        )
        expect_jsonrpc_tool_error(project_error_resp, 9)
      end

      aggregate_failures 'protocol- and dispatch-level failures' do
        unknown_tool_response = jsonrpc_tool_call(200, 'nonexistent_tool')
        expect_jsonrpc_error(unknown_tool_response, 200)

        unknown_method_response = jsonrpc_call(204, 'nonexistent_method')
        expect_jsonrpc_error(unknown_method_response, 204)

        malformed_request = run_mcp_json({ jsonrpc: '2.0', id: 205 })
        malformed_response = parse_jsonrpc(malformed_request[:stdout])
        expect_jsonrpc_error(malformed_response, nil)
      end

      # The mcp gem reports tool-argument validation failures as tools/call
      # results with isError: true, even though validation happens before the
      # tool implementation runs.
      aggregate_failures do
        [
          { id: 201, name: 'file_coverage_summary', arguments: {} },
          # invalid format enum
          {
            id:        202,
            name:      'project_coverage',
            arguments: { root: project_root, resultset: coverage_dir, format: 'invalid_format' },
          },
          # invalid sort_order enum
          {
            id:        203,
            name:      'project_coverage',
            arguments: { root: project_root, resultset: coverage_dir, sort_order: 'invalid' },
          },
        ].each do |request|
          response = jsonrpc_tool_call(request[:id], request[:name], request[:arguments])
          expect_jsonrpc_tool_error(response, request[:id])
        end
      end
    end

    it 'handles raise_on_stale errors with isError: true' do
      require 'tmpdir'
      require 'fileutils'

      Dir.mktmpdir do |tmp_root|
        temp_project_root = File.join(tmp_root, 'project1')
        FileUtils.cp_r(project_root, temp_project_root)

        temp_resultset = File.join(temp_project_root, 'coverage', '.resultset.json')
        resultset = JSON.parse(File.read(temp_resultset))
        resultset['RSpec']['timestamp'] = 1000
        File.write(temp_resultset, JSON.generate(resultset))

        temp_coverage_dir = File.join(temp_project_root, 'coverage')
        stale_env = {
          'RUBY_LIB'       => lib_path,
          'COV_LOUPE_OPTS' => "--mode mcp --root #{temp_project_root} --resultset #{temp_coverage_dir} " \
                              '--log-file /dev/null',
        }

        resp = run_mcp_json(
          jsonrpc_request(10, 'tools/call', {
            name:      'file_coverage_summary',
            arguments: {
              path:           'lib/foo.rb',
              root:           temp_project_root,
              resultset:      temp_coverage_dir,
              raise_on_stale: true,
            },
          }),
          env: stale_env
        )
        response = parse_jsonrpc(resp[:stdout])
        expect_jsonrpc_tool_error(response, 10)
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

      req = jsonrpc_request(10, 'tools/call', { name: 'version', arguments: {} })
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
        jsonrpc_request(101, 'tools/call', { name: 'version', arguments: {} }),
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
