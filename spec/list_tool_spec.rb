# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/list_tool'

RSpec.describe CovLoupe::Tools::ListTool do
  subject(:call_tool) { described_class.call(root: root, server_context: server_context) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
    model = instance_double(CovLoupe::CoverageModel)
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

    payload = {
      'files' => [
        { 'file' => 'lib/foo.rb', 'percent_covered' => 100.0, 'covered' => 10, 'total' => 10,
          'stale' => false },
        { 'file' => 'lib/bar.rb', 'percent_covered' => 50.0,  'covered' => 5,  'total' => 10,
          'stale' => true }
      ],
      'counts' => { 'total' => 2, 'ok' => 1, 'stale' => 1 },
      'skipped_files' => [],
      'missing_tracked_files' => [],
      'newer_files' => [],
      'deleted_files' => [],
      'length_mismatch_files' => [],
      'unreadable_files' => []
    }

    presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
    allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
    allow(presenter).to receive(:relativized_payload).and_return(payload)
  end


  it_behaves_like 'an MCP tool that returns text JSON'

  it 'returns all files coverage data with counts' do
    response = call_tool
    data, _item = expect_mcp_text_json(response, expected_keys: %w[
      files counts skipped_files missing_tracked_files newer_files deleted_files
      length_mismatch_files unreadable_files
    ])

    files = data['files']
    counts = data['counts']

    expect(files.length).to eq(2)
    expect(counts).to include('total' => 2).or include(total: 2)
    expect(files.map { |f| f['file'] }).to eq(%w[lib/foo.rb lib/bar.rb])

    %w[
      skipped_files missing_tracked_files newer_files deleted_files
      length_mismatch_files unreadable_files
    ].each do |key|
      expect(data[key]).to be_empty, "Expected data['#{key}'] to be empty"
    end

    # ok + stale equals total
    ok = counts[:ok] || counts['ok']
    stale = counts[:stale] || counts['stale']
    total = counts[:total] || counts['total']
    expect(ok + stale).to eq(total)
    expect(stale).to eq(1)

    expect(CovLoupe::Presenters::ProjectCoveragePresenter).to have_received(:new).with(
      hash_including(sort_order: :descending)
    )
  end

  describe 'sort_order parameter validation' do
    it 'accepts valid values: ascending, descending, a, d' do
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
