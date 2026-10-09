# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP structured payload schema version' do
  include PayloadSchemaTestHelpers

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:no_timestamp_root) { (FIXTURES_DIR / 'project_no_timestamp').to_s }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  [
    ['file_coverage_summary', 'summary', { path: 'lib/foo.rb' }],
    ['file_coverage_raw', 'raw', { path: 'lib/foo.rb' }],
    ['file_uncovered_lines', 'uncovered', { path: 'lib/foo.rb' }],
    ['file_coverage_detailed', 'detailed', { path: 'lib/foo.rb' }],
    ['project_coverage', 'list', {}],
    ['project_coverage_totals', 'totals', {}],
    ['project_validate', 'validate_result', { code: '->(model) { true }' }],
    ['help', 'help', {}],
  ].each do |tool_name, schema_name, arguments|
    it "puts schema_version first for #{tool_name}" do
      tool_class = CovLoupe::MCPServer::TOOLSET.find { |tool| tool.tool_name == tool_name }
      response = tool_class.call(**arguments, root: root, server_context: server_context)
      data = JSON.parse(response.content.first['text'])

      expect(response).not_to be_error
      expect(data.keys.first).to eq('schema_version')
      expect(data['schema_version']).to eq(CovLoupe::SCHEMA_VERSION)
      expect_schema_valid(schema_name, data)
    end
  end

  it 'puts schema_version first for project_coverage YAML' do
    response = CovLoupe::Tools::ProjectCoverageTool.call(root: root, format: 'yaml',
      server_context: server_context)
    data = YAML.safe_load(response.content.first['text'])

    expect(data.keys.first).to eq('schema_version')
    expect(data['schema_version']).to eq(CovLoupe::SCHEMA_VERSION)
    expect_schema_valid('list', data)
  end

  [
    %w[project_coverage list],
    %w[project_coverage_totals totals],
  ].each do |tool_name, schema_name|
    it "validates #{tool_name} warnings when the timestamp is missing" do
      tool_class = CovLoupe::MCPServer::TOOLSET.find { |tool| tool.tool_name == tool_name }
      response = tool_class.call(root: no_timestamp_root, server_context: server_context)
      data = JSON.parse(response.content.first['text'])

      expect(data['warnings']).not_to be_empty
      expect_schema_valid(schema_name, data)
    end
  end

  it 'validates a stale file response' do
    response = CovLoupe::Tools::FileCoverageSummaryTool.call(path: 'lib/sample.rb',
      root: no_timestamp_root, server_context: server_context)
    data = JSON.parse(response.content.first['text'])

    expect(data['stale']).to eq('length_mismatch')
    expect_schema_valid('summary', data)
  end

  it 'validates project coverage with missing tracked files' do
    response = CovLoupe::Tools::ProjectCoverageTool.call(root: root,
      tracked_globs: ['lib/**/*.rb'], server_context: server_context)
    data = JSON.parse(response.content.first['text'])

    expect(data['missing_tracked_files']).not_to be_empty
    expect_schema_valid('list', data)
  end

  it 'returns a Boolean result for a non-Boolean predicate' do
    response = CovLoupe::Tools::ProjectValidateTool.call(root: root,
      code: '->(_model) { 42 }', server_context: server_context)
    data = JSON.parse(response.content.first['text'])

    expect(data['result']).to be(true)
    expect_schema_valid('validate_result', data)
  end
end
