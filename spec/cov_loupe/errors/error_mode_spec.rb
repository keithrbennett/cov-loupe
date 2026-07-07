# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Error Mode System' do
  let(:test_logger) do
    Class.new do
      attr_reader :messages

      def initialize = @messages = []
      def error(msg) = @messages << msg
    end.new
  end

  let(:test_error) { StandardError.new('Test error message') }

  describe 'ErrorHandler error modes' do
    context 'with error_mode: :off' do
      subject(:handler) { CovLoupe::ErrorHandler.new(error_mode: :off, logger: test_logger) }

      it 'does not log errors' do
        expect(handler.log_errors?).to be false
        expect(handler.show_stack_traces?).to be false

        handler.handle_error(test_error, context: 'test', reraise: false)
        expect(test_logger.messages).to be_empty
      end
    end

    context 'with error_mode: :log' do
      subject(:handler) { CovLoupe::ErrorHandler.new(error_mode: :log, logger: test_logger) }

      it 'logs errors but not stack traces' do
        expect(handler.log_errors?).to be true
        expect(handler.show_stack_traces?).to be false

        handler.handle_error(test_error, context: 'test', reraise: false)
        logged_message = test_logger.messages.join
        expect(logged_message).to include('Error in test: StandardError: Test error message')
        expect(logged_message).not_to include('spec/error_mode_spec.rb') # No stack trace
      end
    end

    context 'with error_mode: :debug' do
      subject(:handler) { CovLoupe::ErrorHandler.new(error_mode: :debug, logger: test_logger) }

      it 'logs errors with stack traces' do
        expect(handler.log_errors?).to be true
        expect(handler.show_stack_traces?).to be true

        # Create an error with a proper backtrace
        begin
          raise StandardError, 'Test error message'
        rescue => e
          handler.handle_error(e, context: 'test', reraise: false)
        end

        logged_message = test_logger.messages.join
        expect(logged_message).to include('Error in test: StandardError: Test error message')
        expect(logged_message).to include('spec/cov_loupe/errors/error_mode_spec.rb') # Stack trace included
      end
    end
  end

  describe 'ErrorHandlerFactory' do
    it 'creates handlers with correct modes' do
      {
        for_cli:        :debug,
        for_library:    :off,
        for_mcp_server: :log,
      }.each do |factory_method, mode|
        handler = CovLoupe::ErrorHandlerFactory.public_send(factory_method, error_mode: mode)
        expect(handler.error_mode).to eq(mode)
      end
    end
  end

  describe 'MCP Tools error mode support' do
    before { setup_mcp_response_stub }

    it 'BaseTool.handle_mcp_error respects error modes' do
      test_error = StandardError.new('Test MCP error')

      # Test different error modes
      %i[off log debug].each do |mode|
        expect(CovLoupe::ErrorHandlerFactory)
          .to receive(:for_mcp_server).with(error_mode: mode).and_call_original

        response = CovLoupe::BaseTool.handle_mcp_error(test_error, 'TestTool', error_mode: mode)
        expect_mcp_tool_error(response)
        expect(response.content.first['text']).to include('Error:')
      end
    end

    it 'BaseTool.handle_mcp_error falls back to :log for invalid error_mode' do
      test_error = StandardError.new('Test MCP error')

      # Test invalid error modes (string and symbol) fall back to :log
      ['invalid_mode', :invalid_mode, 'bad', :bad, 123, nil, {}, []].each do |invalid_mode|
        expect(CovLoupe::ErrorHandlerFactory)
          .to receive(:for_mcp_server).with(error_mode: :log).and_call_original

        response = CovLoupe::BaseTool.handle_mcp_error(
          test_error, 'TestTool', error_mode: invalid_mode
        )
        expect_mcp_tool_error(response)
        expect(response.content.first['text']).to include('Error:')
      end
    end
  end

  describe 'CLI error mode support' do
    let(:project_dir) { File.join(__dir__, 'fixtures', 'project1') }

    it 'accepts --error-mode flag' do
      cli = CovLoupe::CoverageCLI.new

      # Test that the option parser accepts the flag
      expect do
        cli.send(:parse_options!, %w[--error-mode debug summary lib/foo.rb])
      end.not_to raise_error

      expect(cli.config.error_mode).to eq(:debug)
    end

    it 'creates error handler with specified mode' do
      cli = CovLoupe::CoverageCLI.new
      cli.send(:parse_options!, %w[--error-mode off summary lib/foo.rb])

      expect(cli.send(:error_handler).error_mode).to eq(:off)
    end

    it 'validates error mode values' do
      cli = CovLoupe::CoverageCLI.new

      expect do
        cli.send(:parse_options!, %w[--error-mode invalid summary lib/foo.rb])
      end.to raise_error(OptionParser::InvalidArgument)
    end
  end

  describe 'Error mode validation' do
    it 'raises ArgumentError for invalid error modes' do
      expect do
        CovLoupe::ErrorHandler.new(error_mode: :invalid)
      end.to raise_error(ArgumentError, /Invalid error_mode: :invalid/)
    end

    it 'accepts all valid error modes' do
      %i[off log debug].each do |mode|
        expect { CovLoupe::ErrorHandler.new(error_mode: mode) }.not_to raise_error
      end
    end
  end
end
