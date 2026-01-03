# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model'
require_relative '../predicate_evaluator'

module CovLoupe
  module Tools
    class ValidateTool < BaseTool
      description <<~DESC
        Validates coverage data against a predicate (Ruby code that evaluates to true/false).
        Use this to enforce coverage policies programmatically.
        Inputs: Either 'code' (Ruby string) OR 'file' (path to Ruby file), plus optional root/resultset/raise_on_stale/error_mode.
        Output: JSON object {"result": Boolean} where true means policy passed, false means failed.
        On error (syntax error, file not found, etc.), returns an MCP error response.
        Security Warning: Predicates execute as arbitrary Ruby code with full system privileges.
        Examples:
        - "Check if all files have at least 80% coverage" → {"code": "->(m) { m.list['files'].all? { |f| f['percent_covered'] >= 80 } }"}
        - "Run coverage policy from file" → {"file": "coverage_policy.rb"}
      DESC

      input_schema(**coverage_schema(
        additional_properties: {
          code: {
            type: 'string',
            description: 'Ruby code string that returns a callable predicate. ' \
                         'Must evaluate to a lambda, proc, or object with #call method.'
          },
          file: {
            type: 'string',
            description:
              'Path to Ruby file containing predicate code (absolute or relative to root).'
          }
        }
      ))
      class << self
        def call(code: nil, file: nil, root: nil, resultset: nil, raise_on_stale: nil,
          error_mode: 'log', server_context:)
          with_error_handling('ValidateTool', error_mode: error_mode) do
            model, config = create_configured_model(
              server_context: server_context,
              root: root,
              resultset: resultset,
              raise_on_stale: raise_on_stale
            )

            result = if code
              PredicateEvaluator.evaluate_code(code, model)
            elsif file
              # Resolve file path relative to root if needed
              predicate_path = File.expand_path(file, config[:root])
              PredicateEvaluator.evaluate_file(predicate_path, model)
            else
              raise UsageError, "Either 'code' or 'file' must be provided"
            end

            respond_json({ result: result }, name: 'validate_result.json', pretty: true)
          end
        end
      end
    end
  end
end
