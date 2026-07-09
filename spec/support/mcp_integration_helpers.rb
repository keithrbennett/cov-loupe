# frozen_string_literal: true

module Spec
  module Support
    module McpIntegrationHelpers
      def jsonrpc_request(id, method, params = nil)
        request = { jsonrpc: '2.0', id: id, method: method }
        request[:params] = params if params
        request
      end

      def jsonrpc_call(id, method, params = nil)
        result = run_mcp_json(jsonrpc_request(id, method, params))
        parse_jsonrpc(result[:stdout])
      end

      def jsonrpc_tool_call(id, name, arguments = {})
        jsonrpc_call(id, 'tools/call', { name: name, arguments: arguments })
      end

      def parse_jsonrpc(output)
        lines = output.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
          .lines
          .map(&:strip)
          .reject(&:empty?)

        lines.each do |line|
          parsed = JSON.parse(line)
          return parsed if parsed['jsonrpc'] == '2.0'
        rescue JSON::ParserError
          # Continue searching
        end
        raise "No valid JSON-RPC response found. Output: #{output.inspect}"
      end

      def expect_jsonrpc_result(response, id)
        expect(response).to include('jsonrpc' => '2.0', 'id' => id)
        expect(response).to have_key('result')
        response['result']
      end

      def expect_jsonrpc_error(response, id)
        expect(response).to include('jsonrpc' => '2.0', 'id' => id)
        expect_jsonrpc_error_without_id(response)
      end

      def expect_jsonrpc_error_without_id(response)
        expect(response).to include('jsonrpc' => '2.0')
        expect(response).to have_key('error'),
          'expected a JSON-RPC error response, ' \
          "got result: #{response['result'].inspect}"
        expect(response['error']).to have_key('message')
      end

      # Asserts a failed tools/call result, including argument-validation and
      # tool-execution failures. JSON-RPC errors are reserved for protocol- or
      # dispatch-level failures such as unknown tools.
      def expect_jsonrpc_tool_error(response, id)
        expect(response).to include('jsonrpc' => '2.0', 'id' => id)
        expect(response).to have_key('result'),
          "expected a tools/call result for id #{id}, " \
          "got error: #{response['error'].inspect}"
        result = response['result']
        expect(result['isError']).to be(true),
          "expected isError: true for id #{id}, " \
          "got result: #{result.inspect}"
        text = result.dig('content', 0, 'text').to_s
        expect(text.downcase).to match(/error|invalid|not found|required/)
      end
    end
  end
end
