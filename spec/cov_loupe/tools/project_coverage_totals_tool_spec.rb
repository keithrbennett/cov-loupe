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
      'lines'            => {
        'total'          => 42,
        'covered'        => 40,
        'uncovered'      => 2,
        'percentage'     => 95.24,
        'included_files' => 4,
        'excluded_files' => 0,
      },
      'tracking'         => {
        'enabled' => true,
        'globs'   => ['lib/**/*.rb'],
      },
      'files'            => {
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
            'missing_from_coverage' => 0,
            'unreadable'            => 0,
            'skipped'               => 0,
          },
        },
      },
      'timestamp_status' => 'ok',
    }

    presenter = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
    allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new).and_return(presenter)
    allow(presenter).to receive(:relativized_payload).and_return(payload)
  end

  it_behaves_like 'an MCP tool that returns text JSON'

  it 'returns aggregated totals' do
    data, = expect_mcp_text_json(tool_response, expected_keys: %w[lines tracking files])

    expect(data['lines']).to include(
      'total'          => 42,
      'covered'        => 40,
      'uncovered'      => 2,
      'percentage'     => 95.24,
      'included_files' => 4,
      'excluded_files' => 0
    )
    expect(data['files']).to include('total' => 4)
    expect(data['tracking']).to include('enabled' => true)
  end

  it 'includes tracking metadata in output' do
    data, = expect_mcp_text_json(
      tool_response,
      expected_keys: %w[lines tracking files]
    )

    expect(data['tracking']).to include('enabled' => true)
    expect(data['tracking']['globs']).to eq(['lib/**/*.rb'])
  end

  describe 'timestamp_status warnings' do
    let(:setup_presenter_with_timestamp_status) do
      ->(status) do
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

        test_payload = {
          'lines'            => { 'total' => 0, 'covered' => 0, 'uncovered' => 0, 'percentage' => 0,
                       'included_files' => 0, 'excluded_files' => 0 },
          'tracking'         => { 'enabled' => false, 'globs' => [] },
          'files'            => {
            'total'         => 0,
            'with_coverage' => {
              'total' => 0,
              'ok'    => 0,
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
          },
          'timestamp_status' => status,
        }

        presenter = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
        allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new).and_return(presenter)
        allow(presenter).to receive(:relativized_payload).and_return(test_payload)
      end
    end

    it 'includes warnings array when timestamp_status is missing' do
      setup_presenter_with_timestamp_status.call('missing')

      response = described_class.call(root: root, server_context: server_context)
      data, _item = expect_mcp_text_json(response, expected_keys: %w[
        lines tracking files timestamp_status warnings
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
