# frozen_string_literal: true

require_relative '../base_tool'

module CovLoupe
  module Tools
    # @api private
    class VersionTool < BaseTool
      tool_name 'version'
      description <<~DESC
        Use this when the user or client needs to confirm which version of cov-loupe is running.
        This tool takes only the optional output_chars and returns only the version string; avoid it for coverage data.
        Output: plain text line "CovLoupe version: x.y.z".
        Example: "What version of cov-loupe is installed?".
      DESC
      input_schema(
        type:                 'object',
        additionalProperties: false,
        properties:           {
          output_chars: COMMON_PROPERTIES[:output_chars],
        }
      )
      class << self
        # NOTE: output_chars is accepted for consistency with the other tools; the version string
        # has no decoration, so it has no effect beyond being validated.
        def call(output_chars: nil, server_context: nil, **_args)
          with_error_handling(error_label, server_context: server_context) do
            resolve_output_chars(output_chars, server_context) # validates the value
            respond_text("CovLoupe version: #{CovLoupe::VERSION}")
          end
        end
      end
    end
  end
end
