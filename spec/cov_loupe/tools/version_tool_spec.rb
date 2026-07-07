# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/version_tool'

RSpec.describe CovLoupe::Tools::VersionTool do
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  describe '.call' do
    it 'returns a valid MCP response with the correct version string' do
      response = described_class.call(server_context: server_context)
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.content.size).to eq(1)

      item = response.content.first
      expect(item[:type] || item['type']).to eq('text')
      expect(item['text']).to eq("CovLoupe version: #{CovLoupe::VERSION}")
    end

    context 'when error_mode is specified' do
      %w[off log debug].each do |mode|
        it "accepts error_mode '#{mode}' without affecting output" do
          response = described_class.call(error_mode: mode, server_context: server_context)
          item = response.content.first
          expect(item['text']).to eq("CovLoupe version: #{CovLoupe::VERSION}")
        end
      end
    end

    context 'when additional arguments are passed' do
      it 'ignores additional arguments gracefully' do
        response = described_class.call(
          server_context: server_context,
          extra_arg:      'value',
          another:        { nested: 'data' }
        )
        item = response.content.first
        expect(item['text']).to eq("CovLoupe version: #{CovLoupe::VERSION}")
      end
    end

    context 'when an error occurs' do
      it 'returns an MCP tool result with isError: true' do
        # Force an error by hiding VERSION so const_missing is triggered
        hide_const('CovLoupe::VERSION')
        allow(CovLoupe).to receive(:const_missing).with(:VERSION)
          .and_raise(StandardError, 'Version access error')

        response = described_class.call(error_mode: 'log', server_context: server_context)

        expect_mcp_tool_error(response)
        item = response.content.first
        expect(item[:type] || item['type']).to eq('text')
        expect(item['text']).to include('Error')
      end

      it 'handles errors in the response creation process' do
        # Force an error by mocking string interpolation to fail
        version_obj = double('VERSION')
        allow(version_obj).to receive(:to_s).and_raise(StandardError, 'String conversion error')

        # Replace VERSION with our mock object
        stub_const('CovLoupe::VERSION', version_obj)

        response = described_class.call(error_mode: 'log', server_context: server_context)

        expect_mcp_tool_error(response)
        item = response.content.first
        expect(item[:type] || item['type']).to eq('text')
        expect(item['text']).to include('Error')
      end

      it 'respects error_mode setting when handling errors' do
        # Force an error using a mock VERSION that raises an exception
        version_obj = double('VERSION')
        allow(version_obj).to receive(:to_s).and_raise(StandardError, 'Version error')
        stub_const('CovLoupe::VERSION', version_obj)

        %w[off debug].each do |mode|
          response = described_class.call(error_mode: mode, server_context: server_context)

          expect_mcp_tool_error(response)
          item = response.content.first
          expect(item[:type] || item['type']).to eq('text')
          expect(item['text']).to include('Error:')
          expect(item['text']).to include('Version error')
        end
      end
    end
  end
end
