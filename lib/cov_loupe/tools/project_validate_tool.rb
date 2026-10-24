# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model/model'
require_relative '../config/predicate_evaluator'

module CovLoupe
  module Tools
    # @api private
    class ProjectValidateTool < BaseTool
      tool_name 'project_validate'
      description <<~DESC
        Validates coverage data against a predicate (Ruby code that evaluates to true/false).
        Use this to enforce coverage policies programmatically.
        Inputs: Either 'code' (Ruby string) OR 'file' (path to Ruby file), plus optional root/coverage_file/raise_on_stale/error_mode/output_chars.
        Output: JSON object {"schema_version": Integer, "result": Boolean} where true means policy passed (the predicate's return value is coerced by truthiness, as in the CLI). A false result means the policy failed but the tool itself succeeded (the response carries `isError: false`); execution errors (syntax error, file not found, etc.) return a `tools/call` result with `isError: true` and the friendly error message in the content.
        Security Warning: Predicates execute as arbitrary Ruby code with full system privileges.
        A predicate must not print to stdout, which carries the MCP protocol; use $stderr.
        Examples:
        - "Check if all files have at least 80% coverage" → {"code": "->(m) { m.list['files'].all? { |f| f['percentage'].nil? || f['percentage'] >= 80 } }"}
        - "Run coverage policy from file" → {"file": "coverage_policy.rb"}
      DESC

      def self.executes_code? = true

      input_schema(**coverage_schema(
        additional_properties: {
          code: {
            type:        'string',
            description: 'Ruby code string that returns a callable predicate. ' \
                         'Must evaluate to a lambda, proc, or object with #call method.',
          },
          file: {
            type:        'string',
            description:
                         'Path to Ruby file containing predicate code (absolute or relative to root).',
          },
        }
      ))
      class << self
        def call(code: nil, file: nil, root: nil, coverage_file: nil,
          raise_on_stale: nil, error_mode: nil, output_chars: nil, server_context:)
          # Resolve (and validate) output_chars for formatting the successful result
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('ProjectValidateTool', error_mode: error_mode,
            server_context: server_context) do
            # MCPServer#toolset already omits this tool; this also covers servers built from TOOLSET.
            unless available_in?(server_context)
              raise UsageError,
                'project_validate is disabled; start the MCP server with --allow-code-predicates'
            end

            model, config = create_configured_model(
              server_context: server_context,
              root:           root,
              coverage_file:  coverage_file,
              raise_on_stale: raise_on_stale
            )

            result = if code && file
              raise UsageError, "Only one of 'code' or 'file' must be provided, not both"
            elsif code
              PredicateEvaluator.evaluate_code(code, model)
            elsif file
              # Resolve file path relative to root if needed
              predicate_path = File.expand_path(file, config[:root])
              PredicateEvaluator.evaluate_file(predicate_path, model)
            else
              raise UsageError, "Either 'code' or 'file' must be provided"
            end

            respond_json({ result: result }, pretty: true, output_chars: output_chars_sym)
          end
        end
      end
    end
  end
end
