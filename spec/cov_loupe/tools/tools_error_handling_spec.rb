# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/help_tool'
require 'cov_loupe/tools/version_tool'
require 'cov_loupe/tools/file_coverage_summary_tool'
require 'cov_loupe/tools/file_coverage_raw_tool'
require 'cov_loupe/tools/file_uncovered_lines_tool'
require 'cov_loupe/tools/file_coverage_detailed_tool'
require 'cov_loupe/tools/project_coverage_totals_tool'

RSpec.describe CovLoupe::Tools do
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  shared_examples 'handles tool error' do |tool_class, method, error_msg, call_args = {}|
    it "handles errors during #{method} execution" do
      # If we're mocking CoverageModel.new directly (for tools that fail early)
      if method == :new
        allow(CovLoupe::CoverageModel).to receive(:new).and_raise(StandardError, error_msg)
      else
        # For tools that fail on a model method
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
        allow(model).to receive(method).and_raise(StandardError, error_msg)
      end

      default_args = { error_mode: 'log', server_context: server_context }
      response = tool_class.call(**default_args, **call_args)

      expect_mcp_tool_error(response)
      item = response.content.first
      expect(item[:type] || item['type']).to eq('text')
      expect(item['text']).to include('Error')
    end
  end

  # NOTE: VersionTool is covered directly in version_tool_spec.rb, which now
  # asserts the error flag and wire shape for VERSION access and response
  # creation failures, so it is intentionally omitted here.

  describe CovLoupe::Tools::HelpTool do
    it 'returns tool information without errors' do
      response = described_class.call(error_mode: 'log', server_context: server_context)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response).not_to be_error
      item = response.content.first
      expect(item[:type] || item['type']).to eq('text')

      data = JSON.parse(item['text'])
      expect(data).to have_key('tools')
      expect(data['tools']).not_to be_empty
    end
  end

  describe CovLoupe::Tools::FileCoverageSummaryTool do
    it_behaves_like 'handles tool error', described_class, :new, 'Model error', path: 'lib/foo.rb'
  end

  describe CovLoupe::Tools::FileCoverageRawTool do
    it_behaves_like 'handles tool error', described_class, :raw_for, 'Raw data error',
      path: 'lib/foo.rb'
  end

  describe CovLoupe::Tools::FileUncoveredLinesTool do
    it_behaves_like 'handles tool error', described_class, :uncovered_for, 'Uncovered error',
      path: 'lib/foo.rb'
  end

  describe CovLoupe::Tools::FileCoverageDetailedTool do
    it_behaves_like 'handles tool error', described_class, :detailed_for, 'Detailed error',
      path: 'lib/foo.rb'
  end

  describe CovLoupe::Tools::ProjectCoverageTotalsTool do
    it_behaves_like 'handles tool error', described_class, :new, 'Model error'
  end
end
