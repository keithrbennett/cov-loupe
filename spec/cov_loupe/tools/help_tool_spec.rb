# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/help_tool'

RSpec.describe CovLoupe::Tools::HelpTool do
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  it 'returns guidance for each registered tool' do
    response = described_class.call(server_context: server_context)
    payload = response.content.first
    expect(payload['type']).to eq('text')
    data = JSON.parse(payload['text'])
    tool_names = data['tools'].map { |entry| entry['tool'] }

    expect(tool_names).to include('file_coverage_summary', 'file_uncovered_lines',
      'project_coverage', 'project_coverage_totals', 'version')
    expect(data['tools']).to all(include('use_when', 'avoid_when', 'inputs'))
  end

  [false, true].each do |allow|
    it "#{allow ? 'lists' : 'omits'} project_validate when allow_code_predicates is #{allow}" do
      context = mcp_server_context(app_config: CovLoupe::AppConfig.new(allow_code_predicates: allow))
      response = described_class.call(server_context: context)
      tool_names = JSON.parse(response.content.first['text'])['tools'].map { |entry| entry['tool'] }

      expect(tool_names.include?('project_validate')).to be(allow)
    end
  end

  it 'includes resources with local readme path' do
    response = described_class.call(server_context: server_context)
    payload = response.content.first
    data = JSON.parse(payload['text'])

    expect(data).to have_key('resources')
    expect(data['resources'].keys).to match_array(%w[repo docs docs-local])
    expect(data['resources']['docs-local']).to end_with('README.md')
  end
end
