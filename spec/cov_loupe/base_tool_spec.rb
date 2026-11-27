# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::BaseTool do
  let(:handler) { CovLoupe::ErrorHandler.new(error_mode: :log, logger: test_logger) }
  let(:test_logger) { recording_logger }

  let(:orig_handler) do
    CovLoupe.error_handler
  rescue
    nil
  end

  before do
    CovLoupe.error_handler = handler
    setup_mcp_response_stub
  end

  after do
    CovLoupe.error_handler = orig_handler if orig_handler
  end

  it 'advertises no static defaults for parameters that default to server settings' do
    defaults = described_class::COMMON_PROPERTIES.slice(:root, :raise_on_stale, :output_chars)
      .transform_values { |property| property[:default] }

    expect(defaults.values).to all(be_nil)
  end

  it 'does not accept a per-call error_mode' do
    expect(described_class::COMMON_PROPERTIES).not_to have_key(:error_mode)
  end

  shared_examples 'friendly response and logged' do
    it 'returns friendly text' do
      resp = described_class.handle_mcp_error(error, tool, error_mode: :log)
      expect(resp).to be_a(MCP::Tool::Response)
      expect(response_text(resp)).to match(expected_pattern)
    end

    it 'signals the error at the tool-result level (isError)' do
      resp = described_class.handle_mcp_error(error, tool, error_mode: :log)
      expect(resp).to be_error
    end

    it 'respects error_mode :off' do
      resp = described_class.handle_mcp_error(error, tool, error_mode: :off)
      expect(resp).to be_a(MCP::Tool::Response)
      expect(response_text(resp)).to match(expected_pattern)
    end

    it 'still signals isError regardless of error_mode' do
      resp = described_class.handle_mcp_error(error, tool, error_mode: :off)
      expect(resp).to be_error
    end

    it 'serializes the error to isError: true' do
      resp = described_class.handle_mcp_error(error, tool, error_mode: :log)
      expect(resp.to_h).to include(isError: true)
    end
  end

  context 'with CovLoupe::Error' do
    let(:error) { CovLoupe::UsageError.new('invalid args') }
    let(:tool) { 'coverage_summary' }
    let(:expected_pattern) { /Error: invalid args/ }
    let(:log_fragment) { 'invalid args' }

    it_behaves_like 'friendly response and logged'
  end

  context 'with standard error' do
    let(:error) { Errno::ENOENT.new('No such file or directory @ rb_sysopen - missing.rb') }
    let(:tool) { 'coverage_raw' }
    let(:expected_pattern) { /Error: .*File not found: missing.rb/ }
    let(:log_fragment) { 'File not found' }

    it_behaves_like 'friendly response and logged'
  end

  describe 'SORT_ORDER_PROPERTY' do
    it 'lists the sort orders in its enum and description' do
      property = described_class::SORT_ORDER_PROPERTY

      aggregate_failures do
        expect(property[:enum]).to eq(%w[ascending descending a d])
        expect(property[:description]).to include('Accepts: a[scending], d[escending].')
        expect(property[:default]).to eq('descending')
      end
    end
  end

  describe '.with_error_handling error mode resolution' do
    [
      ["the server's error mode", :debug, :debug],
      ["'log' when the server sets none", nil, :log],
    ].each do |label, server_mode, expected_mode|
      it "uses #{label}" do
        app_config = server_mode && CovLoupe::AppConfig.new(error_mode: server_mode)
        allow(described_class).to receive(:handle_mcp_error)

        described_class.with_error_handling('test_tool',
          server_context: mcp_server_context(app_config: app_config)) { raise 'boom' }

        expect(described_class).to have_received(:handle_mcp_error)
          .with(instance_of(RuntimeError), 'test_tool', error_mode: expected_mode)
      end
    end
  end

  describe '.coverage_schema' do
    it 'omits "required" key when required array is empty' do
      schema = described_class.coverage_schema
      expect(schema).to be_a(Hash)
      expect(schema).not_to have_key(:required)
    end

    it 'includes "required" key when required array is provided' do
      required_fields = ['field1']
      schema = described_class.coverage_schema(required: required_fields)
      expect(schema).to have_key(:required)
      expect(schema[:required]).to eq(required_fields)
    end
  end

  describe '.model_config_for' do
    let(:defaults) do
      { root: '.', coverage_file: nil, raise_on_stale: false, file_globs: [] }
    end

    # Helper to mock AppContext with a specific config
    def context_with_config(config_hash)
      app_config = instance_double('AppConfig', model_options: config_hash)
      instance_double('AppContext', app_config: app_config)
    end

    it 'uses defaults when no context or params are provided' do
      config = described_class.model_config_for(server_context:
        instance_double('AppContext', app_config: nil))
      expect(config).to eq(defaults)
    end

    it 'uses app_config over defaults' do
      cli_config = { root: '/cli/root', raise_on_stale: true }
      context = context_with_config(cli_config)

      config = described_class.model_config_for(server_context: context)

      expect(config[:root]).to eq('/cli/root')
      expect(config[:raise_on_stale]).to be(true)
      # coverage_file remains nil (default) if not in cli_config
      expect(config[:coverage_file]).to be_nil
    end

    it 'uses explicit params over app_config' do
      cli_config = { root: '/cli/root', raise_on_stale: true }
      context = context_with_config(cli_config)

      # Pass explicit raise_on_stale: false
      config = described_class.model_config_for(
        server_context: context,
        raise_on_stale: false
      )

      expect(config[:root]).to eq('/cli/root') # inherited from CLI
      expect(config[:raise_on_stale]).to be(false) # overridden by explicit
    end

    it 'uses explicit params over defaults when app_config is nil' do
      context = instance_double('AppContext', app_config: nil)

      config = described_class.model_config_for(
        server_context: context,
        root:           '/explicit/root'
      )

      expect(config[:root]).to eq('/explicit/root')
      expect(config[:raise_on_stale]).to be(false) # default
    end

    it 'ignores nil values in explicit params allowing fallbacks' do
      cli_config = { root: '/cli/root' }
      context = context_with_config(cli_config)

      # explicit root is nil, should fallback to cli_config
      config = described_class.model_config_for(
        server_context: context,
        root:           nil
      )

      expect(config[:root]).to eq('/cli/root')
    end
  end

  describe '.with_model' do
    let(:root) { (FIXTURES_DIR / 'project1').to_s }

    it 'yields the model, the merged config, and the resolved output_chars' do
      yielded = nil
      described_class.with_model(server_context: null_server_context, output_chars: 'a',
        root: root, coverage_file: FIXTURE_PROJECT1_COVERAGE_PATH) do |*args|
        yielded = args
        described_class.respond_text('ok')
      end

      model, config, chars = yielded
      expect(model).to be_a(CovLoupe::CoverageModel)
      expect(config).to include(root: root, raise_on_stale: false)
      expect(chars).to eq(:ascii)
    end

    it 'creates the model for a root that is not a directory on disk' do
      root = '/test/project'
      mock_coverage_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP)
      coverage_file_path = File.join(root, 'coverage', 'coverage.json')
      mock_file_stat(coverage_file_path, mtime: Time.at(FIXTURE_COVERAGE_TIMESTAMP))
      mock_file_digest(coverage_file_path)

      model = nil
      described_class.with_model(server_context: mcp_server_context, root: root) do |m, *|
        model = m
        described_class.respond_text('ok')
      end

      expect(model).to be_a(CovLoupe::CoverageModel)
    end

    it 'returns an error response for an invalid output_chars' do
      response = described_class.with_model(server_context: null_server_context,
        output_chars: 'bogus', root: root) { raise 'not reached' }

      expect_mcp_tool_error(response)
      expect(response_text(response)).to include('Invalid output_chars value')
    end

    it 'returns an error response naming the MCP tool when a code tool is not allowed' do
      response = CovLoupe::Tools::ProjectValidateTool.with_model(server_context: null_server_context,
        root: root) { raise 'not reached' }

      expect_mcp_tool_error(response)
      expect(response_text(response)).to eq(
        'Error: project_validate is disabled; start the MCP server with --allow-code-predicates'
      )
    end
  end

  describe '.error_label' do
    it 'is the class name without its namespace' do
      expect(CovLoupe::Tools::ProjectCoverageTool.error_label).to eq('ProjectCoverageTool')
    end
  end

  describe '.respond_text' do
    it 'wraps the text in one text content item, flagged as an error only when asked' do
      response = described_class.respond_text('hello')

      expect(response.content).to eq([{ 'type' => 'text', 'text' => 'hello' }])
      expect(response).not_to be_error
      expect(described_class.respond_text('bad', error: true)).to be_error
    end
  end

  describe '.respond_json' do
    it 'puts schema_version first without changing the input' do
      payload = { 'ok' => true }
      response = described_class.respond_json(payload)
      data = response_json(response)

      expect(data.keys.first).to eq('schema_version')
      expect(data['schema_version']).to eq(CovLoupe::SCHEMA_VERSION)
      expect(payload).to eq('ok' => true)
    end

    it 'rejects non-hash payloads' do
      expect { described_class.respond_json([]) }.to raise_error(TypeError, /must be a Hash/)
    end

    it 'does not flag successful responses as errors' do
      response = described_class.respond_json({ 'ok' => true })

      expect(response).not_to be_error
    end

    it 'produces ASCII-only JSON when output_chars is :ascii' do
      payload = { 'name' => 'café', 'arrow' => '→' }
      response = described_class.respond_json(payload, output_chars: :ascii)

      json_text = response_text(response)
      expect(json_text).not_to include('é')
      expect(json_text).not_to include('→')
      expect(json_text).to include('\\u') # Unicode escape sequences
    end

    it 'preserves Unicode in JSON when output_chars is :fancy' do
      payload = { 'name' => 'café' }
      response = described_class.respond_json(payload, output_chars: :fancy)

      json_text = response_text(response)
      expect(json_text).to include('café')
    end

    it 'uses pretty formatting when requested with ASCII mode' do
      payload = { 'key' => 'valüe' }
      response = described_class.respond_json(payload, pretty: true, output_chars: :ascii)

      json_text = response_text(response)
      expect(json_text).to include("\n") # Pretty formatted
      expect(json_text).not_to include('ü')
    end
  end

  describe '.create_configured_model' do
    let(:context) { mcp_server_context }

    it 'creates fresh model instances each time' do
      Dir.mktmpdir do |root|
        mock_coverage_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP)
        coverage_file_path = File.join(root, 'coverage', 'coverage.json')

        mock_file_stat(coverage_file_path, mtime: Time.at(100))
        mock_file_digest(coverage_file_path)

        model1, = described_class.create_configured_model(server_context: context, root: root)
        model2, = described_class.create_configured_model(server_context: context, root: root)

        # Models are different objects (not cached at model level)
        expect(model2).not_to be(model1)
        # But they share the same underlying cached data
        expect(model2.instance_variable_get(:@cov)).to eq(model1.instance_variable_get(:@cov))
      end
    end

    it 'models share cached data when coverage_file is unchanged' do
      Dir.mktmpdir do |root|
        mock_coverage_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP)
        coverage_file_path = File.join(root, 'coverage', 'coverage.json')

        mock_file_stat(coverage_file_path, mtime: Time.at(100))
        mock_file_digest(coverage_file_path)

        model1, = described_class.create_configured_model(server_context: context, root: root)
        model2, = described_class.create_configured_model(server_context: context, root: root)

        # Data is shared from ModelDataCache
        expect(model1.instance_variable_get(:@cov)).to be(model2.instance_variable_get(:@cov))
      end
    end
  end

  describe '.resolve_output_chars' do
    let(:context) { mcp_server_context }

    context 'with valid string values' do
      it 'accepts full names and abbreviations' do
        [
          ['default', :default],
          ['fancy', :fancy],
          ['ascii', :ascii],
          ['d', :default],
          ['f', :fancy],
          ['a', :ascii],
        ].each do |input, expected|
          expect(described_class.resolve_output_chars(input, context)).to eq(expected)
        end
      end
    end

    context 'with invalid values' do
      it 'raises UsageError for invalid string values' do
        [
          ['invalid', 'Invalid output_chars value.*invalid.*Must be one of'],
          ['xyz123', 'Invalid output_chars value.*xyz123.*Must be one of'],
          ['def', 'Invalid output_chars value.*def.*Must be one of'],
        ].each do |value, pattern|
          expect do
            described_class.resolve_output_chars(value, context)
          end.to raise_error(CovLoupe::UsageError, /#{pattern}/)
        end
      end

      it 'raises UsageError for non-string types' do
        [
          [123, 'Invalid output_chars type.*Integer.*Must be a string'],
          [{ key: 'value' }, 'Invalid output_chars type.*Hash.*Must be a string'],
          [['default'], 'Invalid output_chars type.*Array.*Must be a string'],
        ].each do |value, pattern|
          expect do
            described_class.resolve_output_chars(value, context)
          end.to raise_error(CovLoupe::UsageError, /#{pattern}/)
        end
      end

      it 'does not raise error for nil values (treated as not provided)' do
        # When nil is explicitly passed, it falls through to the if output_chars check
        # and returns default. This distinguishes between "not provided" vs "explicitly provided as nil"
        expect do
          described_class.resolve_output_chars(nil, context)
        end.not_to raise_error
      end
    end

    context 'with symbol values' do
      it 'accepts valid symbols' do
        %i[default fancy ascii].each do |symbol|
          expect(described_class.resolve_output_chars(symbol, context)).to eq(symbol)
        end
      end

      it 'accepts invalid symbols without validation' do
        # Symbols are returned as-is (internal use, not from MCP)
        expect(described_class.resolve_output_chars(:invalid_symbol, context)).to eq(:invalid_symbol)
      end
    end

    context 'with server context fallback' do
      let(:app_config) do
        instance_double('AppConfig', output_chars: :fancy)
      end
      let(:context_with_config) do
        instance_double('AppContext', app_config: app_config)
      end

      it 'uses explicit parameter over server context' do
        expect(described_class.resolve_output_chars('ascii', context_with_config)).to eq(:ascii)
      end

      it 'falls back to server context when parameter is nil' do
        expect(described_class.resolve_output_chars(nil, context_with_config)).to eq(:fancy)
      end

      it 'falls back to default when no parameter or context config' do
        context_no_config = instance_double('AppContext', app_config: nil)
        expect(described_class.resolve_output_chars(nil, context_no_config)).to eq(:default)
      end
    end
  end

  describe '.ascii_mode?' do
    context 'with valid values' do
      it 'returns false for nil' do
        expect(described_class.send(:ascii_mode?, nil)).to be(false)
      end

      it 'returns expected values for symbols' do
        [
          [:default, false],
          [:fancy, false],
          [:ascii, true],
        ].each do |symbol, expected|
          expect(described_class.send(:ascii_mode?, symbol)).to be(expected)
        end
      end

      it 'accepts valid string values and abbreviations' do
        [
          ['default', false],
          ['fancy', false],
          ['ascii', true],
          ['d', false],
          ['f', false],
          ['a', true],
        ].each do |input, expected|
          expect(described_class.send(:ascii_mode?, input)).to be(expected)
        end
      end
    end

    context 'with invalid values' do
      it 'raises UsageError for invalid string values' do
        expect do
          described_class.send(:ascii_mode?, 'invalid')
        end.to raise_error(CovLoupe::UsageError, /Invalid output_chars value.*invalid.*Must be one of/)
      end

      it 'raises UsageError for non-string, non-symbol types' do
        expect do
          described_class.send(:ascii_mode?, 123)
        end.to raise_error(CovLoupe::UsageError, /Invalid output_chars type.*Integer.*Must be a string/)
      end

      it 'raises UsageError for hash values' do
        expect do
          described_class.send(:ascii_mode?, { key: 'value' })
        end.to raise_error(CovLoupe::UsageError, /Invalid output_chars type.*Hash.*Must be a string/)
      end
    end

    context 'with symbol values' do
      it 'accepts valid symbols' do
        [
          [:default, false],
          [:fancy, false],
          [:ascii, true],
        ].each do |symbol, expected|
          expect(described_class.send(:ascii_mode?, symbol)).to be(expected)
        end
      end

      it 'accepts invalid symbols without validation' do
        # Symbols are returned as-is (internal use)
        expect(described_class.send(:ascii_mode?, :invalid_symbol)).to be(false)
      end
    end
  end
end
