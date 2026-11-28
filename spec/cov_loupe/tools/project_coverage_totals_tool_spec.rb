# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/project_coverage_totals_tool'

RSpec.describe CovLoupe::Tools::ProjectCoverageTotalsTool do
  subject(:tool_response) { described_class.call(root: root, server_context: server_context) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
    model = instance_double(CovLoupe::CoverageModel)
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

    payload = {
      'total'            => 42,
      'covered'          => 40,
      'uncovered'        => 2,
      'percentage'       => 95.24,
      'file_globs'       => ['lib/**/*.rb'],
      'file_counts'      => {
        'total'            => 4,
        'with_coverage'    => {
          'total' => 4,
          'ok'    => 4,
          'stale' => {
            'total'   => 0,
            'by_type' => {
              'deleted'         => 0,
              'newer'           => 0,
              'length_mismatch' => 0,
              'unreadable'      => 0,
            },
          },
        },
        'without_coverage' => {
          'total'   => 0,
          'by_type' => {
            'not_in_coverage' => 0,
            'skipped'         => 0,
          },
        },
      },
      'timestamp_status' => 'ok',
    }

    presenter = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
    allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new).and_return(presenter)
    allow(presenter).to receive_messages(payload: payload, timestamp_status: payload['timestamp_status'])
    allow(presenter).to receive(:root_warning)
  end

  it_behaves_like 'an MCP tool that returns text JSON'

  it 'returns aggregated totals' do
    data, = expect_mcp_text_json(tool_response, expected_keys: %w[percentage file_globs file_counts])

    expect(data).to include(
      'total'      => 42,
      'covered'    => 40,
      'uncovered'  => 2,
      'percentage' => 95.24
    )
    expect(data['file_counts']).to include('total' => 4)
    expect(data['file_globs']).to eq(['lib/**/*.rb'])
  end

  it 'includes the file globs in output' do
    data, = expect_mcp_text_json(
      tool_response,
      expected_keys: %w[percentage file_globs file_counts]
    )

    expect(data['file_globs']).to eq(['lib/**/*.rb'])
  end

  it 'passes the file_globs argument to the presenter' do
    described_class.call(root: root, file_globs: ['lib/foo.rb'], server_context: server_context)

    expect(CovLoupe::Presenters::ProjectTotalsPresenter).to have_received(:new)
      .with(hash_including(file_globs: ['lib/foo.rb']))
  end

  describe 'timestamp_status warnings' do
    let(:setup_presenter_with_timestamp_status) do
      ->(status) do
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

        test_payload = empty_totals_payload('timestamp_status' => status)

        presenter = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
        allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new).and_return(presenter)
        allow(presenter).to receive_messages(payload: test_payload, timestamp_status: status)
        allow(presenter).to receive(:root_warning)
      end
    end

    it 'includes warnings array when timestamp_status is missing' do
      setup_presenter_with_timestamp_status.call('missing')

      response = described_class.call(root: root, server_context: server_context)
      data, _item = expect_mcp_text_json(response, expected_keys: %w[
        percentage file_globs file_counts timestamp_status warnings
      ])

      expect(data['timestamp_status']).to eq('missing')
      expect(data['warnings']).to be_an(Array)
      expect(data['warnings']).to include(
        'Coverage timestamps are missing. Time-based staleness checks were skipped.'
      )
    end

    it 'does not include warnings array when timestamp_status is ok' do
      data, _item = expect_mcp_text_json(tool_response)

      expect(data['timestamp_status']).to eq('ok')
      expect(data['warnings']).to be_nil
    end
  end
end
