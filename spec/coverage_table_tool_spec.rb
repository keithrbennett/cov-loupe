# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/coverage_table_tool'

RSpec.describe CovLoupe::Tools::CoverageTableTool do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  def run_tool(raise_on_stale: false)
    # Let real CoverageModel work to test actual format_table behavior
    described_class.call(root: root, raise_on_stale: raise_on_stale,
      server_context: server_context).payload.first['text']
  end

  it 'returns a formatted table as a string' do
    output = run_tool

    # Contains table structure, headers, and file data
    expect(output).to include(
      '┌', '┬', '┐', '│', '├', '┼', '┤', '└', '┴', '┘',
      'File', 'Covered', 'Total', ' │ Stale │',
      'lib/foo.rb', 'lib/bar.rb',
      'Files: total 2, ok 2, stale 0'
    )
  end

  it 'configures CLI to enforce stale checking when requested' do
    model = instance_double(CovLoupe::CoverageModel,
      list: [
        { 'file' => "#{root}/lib/foo.rb", 'percent_covered' => 100.0, 'covered' => 10, 'total' => 10,
          'stale' => false }
      ],
      relativize: ->(payload) { payload },
      format_table: 'Mock table output'
    )
    allow(CovLoupe::CoverageModel).to receive(:new).with(
      root: root,
      resultset: nil,
      raise_on_stale: true,
      tracked_globs: nil
    ).and_return(model)
    allow(model).to receive(:format_table).and_return('Mock table output')

    described_class.call(root: root, raise_on_stale: true, server_context: server_context)

    expect(CovLoupe::CoverageModel).to have_received(:new).with(
      root: root,
      resultset: nil,
      raise_on_stale: true,
      tracked_globs: nil
    )
    expect(model).to have_received(:format_table)
  end

  it 'uses descending sort order by default' do
    model = instance_double(CovLoupe::CoverageModel)
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
    allow(model).to receive(:format_table).and_return('Mock table')

    described_class.call(root: root, server_context: server_context)

    expect(model).to have_received(:format_table).with(
      hash_including(sort_order: :descending)
    )
  end

  describe 'sort_order parameter validation' do
    it 'accepts valid values: ascending, descending, a, d' do
      model = instance_double(CovLoupe::CoverageModel)
      allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
      allow(model).to receive(:format_table).and_return('Mock table')

      %w[ascending descending a d].each do |sort_order|
        response = described_class.call(
          root: root,
          sort_order: sort_order,
          server_context: server_context
        )
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.payload.first['type']).to eq('text')
      end
    end

    it 'rejects invalid sort_order values' do
      response = described_class.call(
        root: root,
        sort_order: 'invalid',
        server_context: server_context
      )
      expect(response).to be_a(MCP::Tool::Response)
      text = response.payload.first['text']
      expect(text).to include('Error')
      expect(text).to include('invalid')
    end
  end
end
