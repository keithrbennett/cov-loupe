# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples/file_based_mcp_tools'

# Load all the tool classes that will be tested
require 'cov_loupe/tools/coverage_summary_tool'
require 'cov_loupe/tools/coverage_raw_tool'
require 'cov_loupe/tools/uncovered_lines_tool'
require 'cov_loupe/tools/coverage_detailed_tool'

RSpec.describe 'File-based MCP Tools' do
  # Test each file-based tool using the shared example with its specific configuration
  FILE_BASED_TOOL_CONFIGS.each_value do |config|
    describe config[:tool_class] do
      it_behaves_like 'a file-based MCP tool', config
    end
  end

  # Test that all file-based tools handle the same parameters consistently
  describe 'parameter consistency' do
    let(:server_context) { null_server_context }

    before do
      setup_mcp_response_stub
    end

    it 'all file-based tools accept the same basic parameters' do
      # Test that all tools can be called with the same parameter signature
      FILE_BASED_TOOL_CONFIGS.each_value do |config|
        stub_coverage_model(
          model_method: config[:model_method],
          mock_data: config[:mock_data],
          file_path: 'lib/example.rb',
          staleness: false
        )

        expect do
          config[:tool_class].call(
            path: 'lib/example.rb',
            root: '.',
            resultset: FIXTURE_PROJECT1_RESULTSET_PATH,
            server_context: server_context
          )
        end.not_to raise_error
      end
    end

    it 'all file-based tools return JSON resources with consistent structure' do
      FILE_BASED_TOOL_CONFIGS.each_value do |config|
        stub_coverage_model(
          model_method: config[:model_method],
          mock_data: config[:mock_data],
          staleness: false
        )

        response = config[:tool_class].call(path: 'lib/foo.rb', server_context: server_context)

        # All should have the same basic MCP text structure
        expect(response.payload).to be_an(Array)
        expect(response.payload.first['type']).to eq('text')
        expect(response.payload.first).to have_key('text')

        # All should return valid JSON
        expect { JSON.parse(response.payload.first['text']) }.not_to raise_error
      end
    end
  end

  # Performance/behavior comparison tests
  describe 'cross-tool consistency' do
    let(:server_context) { null_server_context }

    before do
      setup_mcp_response_stub
    end

    it 'tools that include summary data return consistent summary format' do
      summary_tools = FILE_BASED_TOOL_CONFIGS.select do |_, config|
        config[:expected_keys].include?('summary')
      end

      summary_tools.each_value do |config|
        stub_coverage_model(
          model_method: config[:model_method],
          mock_data: config[:mock_data],
          staleness: false
        )

        response = config[:tool_class].call(path: 'lib/foo.rb', server_context: server_context)
        data = JSON.parse(response.payload.first['text'])

        if data.key?('summary')
          expect(data['summary']).to include('covered', 'total', 'percent_covered')
          expect(data['summary']['percent_covered']).to be_a(Numeric)
        end
      end
    end
  end
end
