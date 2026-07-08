# frozen_string_literal: true

# MCP Tool shared examples and helpers
module MCPToolTestHelpers
  RESPONSE_NOT_GIVEN = Object.new.freeze

  def null_server_context
    instance_double('ServerContext', app_config: nil, mcp_mode?: false)
  end

  def mcp_server_context(app_config: nil)
    instance_double(
      'ServerContext',
      app_config: app_config,
      mcp_mode?:  true
    )
  end

  def setup_mcp_response_stub
    # Standardized MCP::Tool::Response stub that mirrors the real gem class
    # (content, structured_content, error flag, error? predicate, to_h wire
    # serialization) so tests can assert on tool-result-level error signaling via
    # `response.error?` and on the serialized shape via `.to_h`.
    response_class = Class.new do
      attr_reader :content, :structured_content

      def initialize(content = nil, deprecated_error = RESPONSE_NOT_GIVEN, error: false,
        structured_content: nil)
        if deprecated_error != RESPONSE_NOT_GIVEN
          error = deprecated_error
        end

        @content = content || []
        @error = error
        @structured_content = structured_content
      end

      def error?
        !!@error
      end

      def to_h
        { content:, isError: error?, structuredContent: @structured_content }.compact
      end
    end
    stub_const('MCP::Tool::Response', response_class)
  end

  def expect_mcp_text_json(response, expected_keys: [])
    item = response.content.first

    # Check for a 'text' part
    expect(item['type']).to eq('text')
    expect(item).to have_key('text')

    # Parse and validate JSON content
    data = JSON.parse(item['text'])

    # Check for expected keys
    expected_keys.each do |key|
      expect(data).to have_key(key)
    end

    [data, item] # Return for additional custom assertions
  end

  def expect_mcp_tool_error(response)
    expect(response).to be_a(MCP::Tool::Response)
    expect(response).to be_error
    expect(response.to_h).to include(isError: true)
    response
  end
end
