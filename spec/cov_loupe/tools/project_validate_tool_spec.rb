# frozen_string_literal: true

require 'spec_helper'
require 'pathname'
require 'tempfile'
require 'cov_loupe/tools/project_validate_tool'

RSpec.describe CovLoupe::Tools::ProjectValidateTool do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:resultset) { FIXTURE_PROJECT1_RESULTSET_PATH }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  def call_tool(**params)
    described_class.call(**params, root: root, resultset: resultset, server_context: server_context)
  end

  def response_text(response)
    item = response.content.first
    item['text']
  end

  def with_predicate_file(content, dir: nil)
    Tempfile.create(%w[predicate .rb], dir) do |file|
      file.write(content)
      file.flush
      yield file
    end
  end

  shared_examples 'syntax error handling' do |_source, error_message_fragment|
    it 'returns an error for syntax errors' do
      response = call_with_predicate('->(_m) { 1 + }')

      expect_mcp_tool_error(response)
      expect(response_text(response)).to include(error_message_fragment)
    end
  end

  shared_examples 'non-callable handling' do |_source, content|
    it 'returns an error when the predicate is not callable' do
      response = call_with_predicate(content)

      expect_mcp_tool_error(response)
      expect(response_text(response)).to include('Predicate must be callable')
    end
  end

  shared_examples 'false result' do
    it 'returns false when the predicate evaluates to false' do
      response = call_with_predicate('->(_m) { false }')

      expect(response).not_to be_error
      expect(response.to_h).to include(isError: false)
      data, = expect_mcp_text_json(response, expected_keys: %w[result])
      expect(data['result']).to be(false)
    end
  end

  describe '.call' do
    context 'with inline code' do
      def call_with_predicate(code)
        call_tool(code: code)
      end

      it 'evaluates the predicate against the coverage model' do
        expect(CovLoupe::CoverageModel).to receive(:new).and_call_original

        # Realistic coverage policy: foo.rb must have at least 50% coverage
        # Note: model.list now returns a hash, so we access ['files']
        response = call_with_predicate(<<~RUBY)
          ->(m) do
            foo_file = m.list["files"].detect { |f| f["file"].include?("foo.rb") }
            foo_coverage = foo_file["percentage"] if foo_file
            foo_coverage && foo_coverage >= 50.0
          end
        RUBY

        expect(response).not_to be_error
        expect(response.to_h).to include(isError: false)
        data, = expect_mcp_text_json(response, expected_keys: %w[result])
        expect(data['result']).to be(true)
      end

      it_behaves_like 'false result'
      it_behaves_like 'syntax error handling', :code, 'Syntax error in predicate code'
      it_behaves_like 'non-callable handling', :code, '123'

      it 'returns an error when the predicate raises during execution' do
        response = call_with_predicate("->(_m) { raise 'Boom' }")

        expect_mcp_tool_error(response)
        text = response_text(response)
        expect(text).to include('Error:', 'Boom')
        # Verify it's an error response, not a JSON result
        expect(text).not_to include('{"result"')
      end
    end

    context 'with a predicate file' do
      def call_with_predicate(content)
        with_predicate_file(content) do |file|
          call_tool(file: file.path)
        end
      end

      it_behaves_like 'false result'
      it_behaves_like 'syntax error handling', :file, 'Syntax error in predicate file'
      it_behaves_like 'non-callable handling', :file, 'true'

      it 'expands relative paths from the provided root before evaluation' do
        with_predicate_file('->(_m) { true }', dir: root) do |file|
          relative_path = Pathname.new(file.path).relative_path_from(Pathname.new(root)).to_s
          allow(CovLoupe::PredicateEvaluator)
            .to receive(:evaluate_file)
            .and_return(true)

          response = call_tool(file: relative_path)

          expect(CovLoupe::PredicateEvaluator)
            .to have_received(:evaluate_file)
            .with(file.path, kind_of(CovLoupe::CoverageModel))
          data, = expect_mcp_text_json(response, expected_keys: ['result'])
          expect(data['result']).to be(true)
        end
      end

      it 'returns an error when the predicate file is missing' do
        response = call_tool(file: 'missing_predicate.rb')

        expect_mcp_tool_error(response)
        expect(response_text(response)).to include('Predicate file not found')
      end
    end

    it 'returns an error when neither code nor file is provided' do
      response = call_tool

      expect_mcp_tool_error(response)
      expect(response_text(response)).to include("Either 'code' or 'file' must be provided")
    end

    it 'returns an error when both code and file are provided' do
      response = call_tool(code: '->(_m) { true }', file: 'predicate.rb')

      expect_mcp_tool_error(response)
      expect(response_text(response)).to include("Only one of 'code' or 'file' must be provided, not both")
    end
  end
end
