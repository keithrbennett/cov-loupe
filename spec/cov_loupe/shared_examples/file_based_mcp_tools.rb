# frozen_string_literal: true

require 'spec_helper'

# Shared examples for file-based MCP tools that follow the same pattern:
# - Take a path parameter
# - Call a specific method on CoverageModel
# - Return a JSON text payload with consistent structure

RSpec.shared_examples 'a file-based MCP tool' do |config|
  subject { tool_class.call(path: 'lib/foo.rb', server_context: server_context) }

  let(:server_context) { null_server_context }
  let(:tool_class) { config[:tool_class] }
  let(:model_method) { config[:model_method] }
  let(:expected_keys) { config[:expected_keys] }
  let(:mock_data) { config[:mock_data] }
  let(:additional_validations) { config[:additional_validations] }

  before do
    setup_mcp_response_stub
    stub_coverage_model(
      model_method: model_method,
      mock_data:    mock_data,
      file_path:    'lib/foo.rb',
      staleness:    'ok'
    )
  end


  it_behaves_like 'an MCP tool that returns text JSON'

  it "returns #{config[:description]} with expected structure" do
    response = subject
    data, item = expect_mcp_text_json(response, expected_keys: expected_keys)

    if data.is_a?(Hash) && data.key?('file')
      expect(data['file']).to eq('lib/foo.rb')
    end

    expect(data).to have_key('stale')
    expect(data['stale']).to eq('ok')

    # Run tool-specific validations if provided
    if additional_validations
      instance_exec(data, item, &additional_validations)
    end
  end

  # Generate tool-specific examples dynamically
  tool_specific_examples = config[:tool_specific_examples] || {}
  tool_specific_examples.each do |example_name, example_block|
    it example_name do
      expect { instance_exec(config, &example_block) }.not_to raise_error
    end
  end
end

# Configuration data for each file-based MCP tool
FILE_BASED_TOOL_CONFIGS = {
  summary:   {
    tool_class:             CovLoupe::Tools::FileCoverageSummaryTool,
    model_method:           :summary_for,
    expected_keys:          %w[file summary stale],
    description:            'coverage summary data',
    mock_data:              {
      'file'    => '/abs/path/lib/foo.rb',
      'summary' => { 'covered' => 10, 'total' => 12, 'percentage' => 83.33 },
    },
    additional_validations: ->(data, _item) {
      expect(data['summary']).to include('covered', 'total', 'percentage')
    },
    tool_specific_examples: {
      'includes percentage in summary data' => ->(config) {
        stub_coverage_model(
          model_method: :summary_for,
          mock_data:    config[:mock_data],
          staleness:    'ok'
        )
        setup_mcp_response_stub

        response = config[:tool_class].call(path: 'lib/foo.rb',
          server_context: null_server_context)
        data, = expect_mcp_text_json(response)

        expect(data['summary']['percentage']).to be_a(Float)
      },
    },
  },

  raw:       {
    tool_class:             CovLoupe::Tools::FileCoverageRawTool,
    model_method:           :raw_for,
    expected_keys:          %w[file lines stale],
    description:            'raw coverage data',
    mock_data:              {
      'file'  => '/abs/path/lib/foo.rb',
      'lines' => [nil, 1, 0],
    },
    additional_validations: ->(data, _item) {
      expect(data['lines']).to be_an(Array)
    },
  },

  uncovered: {
    tool_class:             CovLoupe::Tools::FileUncoveredLinesTool,
    model_method:           :uncovered_for,
    expected_keys:          %w[file uncovered summary stale],
    description:            'uncovered lines data',
    mock_data:              {
      'file'      => '/abs/path/lib/foo.rb',
      'uncovered' => [5, 9, 12],
      'summary'   => { 'covered' => 10, 'total' => 12, 'percentage' => 83.33 },
    },
    additional_validations: ->(data, _item) {
      expect(data['uncovered']).to eq([5, 9, 12])
    },
    tool_specific_examples: {
      'includes both uncovered lines and summary' => ->(config) {
        stub_coverage_model(
          model_method: :uncovered_for,
          mock_data:    config[:mock_data],
          staleness:    'ok'
        )
        setup_mcp_response_stub

        response = config[:tool_class].call(path: 'lib/foo.rb',
          server_context: null_server_context)
        data, = expect_mcp_text_json(response)

        expect(data['uncovered']).to be_an(Array)
        expect(data['summary']).to include('covered', 'total', 'percentage')
      },
    },
  },

  detailed:  {
    tool_class:             CovLoupe::Tools::FileCoverageDetailedTool,
    model_method:           :detailed_for,
    expected_keys:          %w[file lines summary stale],
    description:            'detailed coverage data',
    mock_data:              {
      'file'    => '/abs/path/lib/foo.rb',
      'lines'   => [
        { 'line' => 1, 'hits' => 1, 'covered' => true },
        { 'line' => 2, 'hits' => 0, 'covered' => false },
      ],
      'summary' => { 'covered' => 1, 'total' => 2, 'percentage' => 50.0 },
    },
    additional_validations: ->(data, _item) {
      expect(data['lines']).to be_an(Array)
      expect(data['lines'].first).to include('line', 'hits', 'covered')
    },
  },
}.freeze
