# frozen_string_literal: true

require 'mcp'
require 'json'
require_relative 'errors/errors'
require_relative 'errors/error_handler'
require_relative 'model/model'
require_relative 'output_chars'
require_relative 'config/option_normalizers'
require_relative 'payload_schema'

module CovLoupe
  # Base class for all MCP tool implementations.
  #
  # Provides shared infrastructure for:
  # - Schema definition (COMMON_PROPERTIES, coverage_schema, PATH_PROPERTY)
  # - Model creation with config merging (server context config → tool params → defaults)
  # - Error handling (with_error_handling wraps all tool calls)
  # - JSON response formatting (respond_json with ASCII mode support)
  # - Output character resolution (resolve_output_chars from tool param or server context)
  #
  # Tool dispatch pattern:
  #   1. Tool class receives call() with JSON params from MCP client
  #   2. Config is merged: server_context.app_config < explicit tool params
  #   3. CoverageModel is created for the call and reuses shared cached data
  #   4. Presenter computes the payload (project-relative paths from the model)
  #   5. respond_json formats the output
  #
  # Coverage tools run through with_model, which also validates output_chars and names the
  # tool for error reporting. File-scope tools (summary, raw, detailed, uncovered) extend
  # CovLoupe::FileTool, whose call infers the model method from the tool class name.
  #
  # @api private
  class BaseTool < ::MCP::Tool
    COMMON_PROPERTIES = {
      root:           {
        type:        'string',
        description: 'Project root used to resolve relative paths ' \
                     "(defaults to the server's --root, '.' unless set).",
      },
      coverage_file:  {
        type:        'string',
        description: 'Path to the SimpleCov coverage.json file, or to a directory ' \
                     'containing one. A relative path is tried against both the server working ' \
                     'directory and root; it is an error if it names different existing locations in each.',
      },
      raise_on_stale: {
        type:        'boolean',
        description: 'If true, raise error if coverage data is stale (deleted or unreadable ' \
          'source files, timestamp or line-count mismatch), or, for project tools, if a file ' \
          "matching the file globs (a file_globs argument, or the server's -g) is not in " \
          'coverage data or a coverage row is skipped. ' \
          "Defaults to the server's --raise-on-stale (false unless set).",
      },
      output_chars:   {
        type:        'string',
        description: "Output character mode: 'default' (UTF-8 encoding uses fancy, else ascii), " \
                     "'fancy' (Unicode table borders), " \
                     "'ascii' (ASCII table borders; JSON escapes non-ASCII). " \
                     'Accepts: d[efault], f[ancy], a[scii]. ' \
                     "Defaults to the server's --output-chars ('default' unless set).",
        enum:        %w[default fancy ascii d f a],
      },
    }.freeze

    FILE_GLOBS_PROPERTY = {
      type:        'array',
      description: 'Report only files matching these glob patterns, and report matching files ' \
                   'that have no coverage data (helps flag new files).',
      items:       { type: 'string' },
    }.freeze

    DEFAULT_SORT_ORDER = CoverageModel::DEFAULT_SORT_ORDER.to_s

    SORT_ORDER_PROPERTY = {
      type:        'string',
      description: 'Sort order for coverage percentages. ' \
                   "'#{DEFAULT_SORT_ORDER}' (default) lists highest coverage first. " \
                   "Accepts: #{OptionNormalizers.sort_order_choices(', ')}.",
      default:     DEFAULT_SORT_ORDER,
      enum:        OptionNormalizers.sort_order_values,
    }.freeze

    PATH_PROPERTY = {
      type:        'string',
      description: 'Path to the file whose coverage data you need, relative to the project root or absolute.',
      examples:    ['lib/my_app/order.rb'],
    }.freeze

    def self.coverage_schema(additional_properties: {}, required: [])
      schema = {
        type:                 'object',
        additionalProperties: false,
        properties:           COMMON_PROPERTIES.merge(additional_properties),
      }
      schema[:required] = required unless required.empty?
      schema.freeze
    end

    # Tools that execute client-supplied Ruby override this to return true. The MCP server
    # registers (and help lists) them only when started with --allow-code-predicates.
    def self.executes_code? = false

    def self.available_in?(server_context)
      !executes_code? || server_context.app_config&.allow_code_predicates == true
    end

    # The tool's class name without its namespace, used to identify it in error logs. User-facing
    # messages name the tool by its MCP name, tool_name, instead.
    def self.error_label = name.split('::').last

    # Wrap tool execution with consistent error handling.
    # Yields to the block and rescues any error, delegating to handle_mcp_error.
    # This eliminates duplicate rescue blocks across all tools.
    #
    # Errors are handled in the server's configured error mode (--error-mode).
    #
    # @param error_label [String] Identifies the tool in error logs (see error_label)
    # @param server_context [AppContext, nil] Server context with app_config
    def self.with_error_handling(error_label, server_context: nil)
      CovLoupe.logger.raise_if_initialization_failed!
      yield
    rescue => e
      error_mode = server_context&.app_config&.error_mode || :log
      handle_mcp_error(e, error_label, error_mode: error_mode)
    end

    # Handle errors consistently across all MCP tools.
    # Returns an MCP::Tool::Response marked as an error (isError: true) so MCP
    # clients can programmatically detect the failure, with the user-friendly
    # message carried in the response content.
    #
    # @param error [Exception] The error to handle
    # @param error_label [String] Identifies the tool in error logs (see error_label)
    # @param error_mode [Symbol] Error handling mode (:off, :log, :debug), from the server config
    # @return [MCP::Tool::Response] Error response (isError: true)
    def self.handle_mcp_error(error, error_label, error_mode: :log)
      error_handler = ErrorHandlerFactory.for_mcp_server(error_mode: error_mode)

      # Normalize to a CovLoupe::Error so we can handle/log uniformly
      normalized = error.is_a?(CovLoupe::Error) \
        ? error : error_handler.convert_standard_error(error)
      begin
        log_mcp_error(normalized, error_label, error_handler)
      rescue LoggingError
        # Logging failure must not replace the original tool error.
      end

      # Preserve the operation error as the primary MCP response. Logging is
      # secondary diagnostics and must not replace or obscure the original error.
      error_message = normalized.user_friendly_message
      # Flag the failure in the tool result via isError: true so MCP clients
      # can distinguish failed tool calls from successful ones, rather than
      # embedding error text in a normal success response. This is the
      # tool-result-level error signal; a JSON-RPC error is reserved for
      # protocol- or dispatch-level failures such as an unknown tool.
      respond_text("Error: #{error_message}", error: true)
    end

    # Respond with a single text content item.
    #
    # @param text [String] The response text
    # @param error [Boolean] Flag the response as a failed tool call (isError: true)
    # @return [MCP::Tool::Response]
    def self.respond_text(text, error: false)
      ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => text }], error: error)
    end

    # Respond with the JSON payload serialized as a single text content item.
    #
    # @param payload [Hash] The data to serialize as JSON
    # @param pretty [Boolean] Use pretty formatting with indentation
    # @param output_chars [Symbol, String, nil] Output character mode (:default, :fancy, :ascii)
    # @return [MCP::Tool::Response] Response containing the JSON string
    def self.respond_json(payload, pretty: false, output_chars: :default)
      ascii_only = ascii_mode?(output_chars)
      payload = PayloadSchema.add(payload)
      json = if pretty
        ascii_only ? JSON.pretty_generate(payload, ascii_only: true) : JSON.pretty_generate(payload)
      else
        ascii_only ? JSON.generate(payload, ascii_only: true) : JSON.generate(payload)
      end
      respond_text(json)
    end

    # Determines if ASCII mode is in effect for the character mode setting.
    # Normalizes string inputs to symbols (MCP JSON provides strings, internal code uses symbols).
    #
    # @param char_mode [Symbol, String, nil] The character mode (:default, :fancy, :ascii)
    # @return [Boolean] true if ASCII mode is in effect
    # @raise [CovLoupe::UsageError] if char_mode is invalid
    def self.ascii_mode?(char_mode)
      return false if char_mode.nil?

      normalized_mode_name = validated_output_chars(char_mode)
      OutputChars.ascii_mode?(normalized_mode_name)
    end
    private_class_method :ascii_mode?

    def self.log_mcp_error(error, error_label, error_handler)
      # Use the provided error handler for logging
      error_handler.send(:log_error, error, error_label)
    end
    private_class_method :log_mcp_error

    # Merges configuration from server context (CLI flags) with explicit tool parameters (JSON).
    # Explicit parameters take precedence over context config, which takes precedence over defaults.
    # @param server_context [AppContext] The server context containing app_config from CLI
    # @param model_option_overrides [Hash] Tool call parameters that override model defaults
    # @return [Hash] Merged configuration for CoverageModel initialization
    def self.model_config_for(server_context:, **model_option_overrides)
      # Start with config from context (CLI flags) or hardcoded defaults
      base = server_context.app_config&.model_options || default_model_options

      # Merge explicit params from JSON, removing nils
      # (nil means "not provided", so use base config)
      base.merge(model_option_overrides.compact)
    end

    # Creates and configures a CoverageModel instance, returning both the model and the configuration.
    # Useful when the tool needs access to the resolved configuration (e.g., root, raise_on_stale).
    #
    # Models are cheap to create because ModelDataCache shares the loaded coverage data,
    # so we create a fresh instance on each call rather than caching at the model level.
    #
    # @param server_context [AppContext] The server context
    # @param model_option_overrides [Hash] Tool call parameters that override model defaults
    # @return [Array<CoverageModel, Hash>] The configured model and the configuration hash
    def self.create_configured_model(server_context:, **model_option_overrides)
      config = model_config_for(server_context: server_context, **model_option_overrides)
      model = CoverageModel.new(**config)
      [model, config]
    end

    # Default configuration when no context or explicit params are provided
    def self.default_model_options
      { root: '.', coverage_file: nil, raise_on_stale: false, file_globs: [] }
    end

    # Resolves output_chars from tool parameter or server context.
    # Tool parameter takes precedence over server context config.
    #
    # @param output_chars [String, Symbol, nil] Tool parameter value
    # @param server_context [AppContext] Server context with app_config
    # @return [Symbol] Normalized output_chars mode (:default, :fancy, or :ascii)
    # @raise [CovLoupe::UsageError] if output_chars parameter is invalid
    def self.resolve_output_chars(output_chars, server_context)
      # Use explicit parameter if provided
      return validated_output_chars(output_chars) if output_chars

      # Fall back to server context config
      server_context.app_config&.output_chars || :default
    end

    # Normalizes an output_chars value: converts a string to a symbol, raising if it is invalid.
    #
    # @param value [String, Symbol, nil] The output_chars value to normalize
    # @return [Symbol] Normalized output_chars mode (:default, :fancy, or :ascii)
    # @raise [CovLoupe::UsageError] if value is invalid
    def self.validated_output_chars(value)
      case value
      when Symbol then value
      when String
        begin
          OptionNormalizers.normalize_output_chars(value)
        rescue OptionParser::InvalidArgument
          raise CovLoupe::UsageError, "Invalid output_chars value: #{value.inspect}. " \
            'Must be one of: default, fancy, ascii (or abbreviations: d, f, a)'
        end
      else
        raise CovLoupe::UsageError, "Invalid output_chars type: #{value.class.name}. " \
          'Must be a string (one of: default, fancy, ascii, or abbreviations: d, f, a)'
      end
    end
    private_class_method :validated_output_chars

    # Runs a coverage tool call with consistent error handling: resolves output_chars, creates
    # the model, and yields it with the merged configuration and the resolved output_chars. A
    # tool that executes code raises UsageError unless the server allows it; MCPServer#toolset
    # already omits such tools, and this also covers servers built from TOOLSET.
    #
    # @param server_context [AppContext] Server context
    # @param output_chars [String, Symbol, nil] Output character mode tool parameter
    # @param model_option_overrides [Hash] Tool call parameters that override model defaults
    # @yieldparam model [CoverageModel]
    # @yieldparam config [Hash] Merged model configuration
    # @yieldparam output_chars [Symbol] Resolved output character mode
    # @return [MCP::Tool::Response] The block's response, or an error response
    def self.with_model(server_context:, output_chars: nil, **model_option_overrides)
      with_error_handling(error_label, server_context: server_context) do
        output_chars_sym = resolve_output_chars(output_chars, server_context)
        unless available_in?(server_context)
          raise UsageError,
            "#{tool_name} is disabled; start the MCP server with --allow-code-predicates"
        end

        model, config = create_configured_model(server_context: server_context,
          **model_option_overrides)
        yield model, config, output_chars_sym
      end
    end
  end
end
