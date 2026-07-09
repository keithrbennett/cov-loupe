# frozen_string_literal: true

require 'mcp'
require 'json'
require_relative 'errors/errors'
require_relative 'errors/error_handler'
require_relative 'model/model'
require_relative 'presenters/coverage_payload_presenter'
require_relative 'output_chars'
require_relative 'config/option_normalizers'

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
  #   4. Presenter computes payload (absolute paths, then relativized)
  #   5. respond_json formats the output
  #
  # File-scope tools (summary, raw, detailed, uncovered) use call_with_file_payload
  # which infers the model method and JSON name from the tool class name.
  class BaseTool < ::MCP::Tool
    COMMON_PROPERTIES = {
      root:           {
        type:        'string',
        description: 'Project root used to resolve relative paths ' \
                     '(defaults to current workspace).',
        default:     '.',
      },
      resultset:      {
        type:        'string',
        description: 'Path to the SimpleCov .resultset.json file (absolute or relative to root).',
      },
      raise_on_stale: {
        type:        'boolean',
        description: 'If true, raise error if coverage data is stale (missing files, ' \
          'timestamp mismatch). Defaults to false.',
        default:     false,
      },
      error_mode:     {
        type:        'string',
        description: "Error handling mode: 'off' (silent), 'log' (log errors), " \
                     "'debug' (verbose with backtraces).",
        enum:        %w[off log debug],
        default:     'log',
      },
      output_chars:   {
        type:        'string',
        description: "Output character mode: 'default' (UTF-8 encoding uses fancy, else ascii), " \
                     "'fancy' (Unicode box-drawing and symbols), 'ascii' (ASCII-only 0x00-0x7F). " \
                     'Accepts: d[efault], f[ancy], a[scii].',
        enum:        %w[default fancy ascii d f a],
        default:     'default',
      },
    }.freeze

    ERROR_MODE_PROPERTY = COMMON_PROPERTIES[:error_mode].freeze

    TRACKED_GLOBS_PROPERTY = {
      type:        'array',
      description: 'Glob patterns for files that should exist in the coverage report' \
                   '(helps flag new files).',
      items:       { type: 'string' },
    }.freeze

    DEFAULT_SORT_ORDER = CoverageModel::DEFAULT_SORT_ORDER.to_s

    SORT_ORDER_PROPERTY = {
      type:        'string',
      description: 'Sort order for coverage percentages. ' \
                   "'#{DEFAULT_SORT_ORDER}' (default) lists highest coverage first. " \
                   'Accepts: a[scending], d[escending].',
      default:     DEFAULT_SORT_ORDER,
      enum:        %w[ascending descending a d],
    }.freeze

    PATH_PROPERTY = {
      type:        'string',
      description: 'Repo-relative or absolute path to the file whose coverage data you need.',
      examples:    ['lib/cov_loupe/model.rb'],
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

    FILE_INPUT_SCHEMA = coverage_schema(
      additional_properties: { path: PATH_PROPERTY },
      required:              ['path']
    )
    def self.input_schema_def = FILE_INPUT_SCHEMA

    # Wrap tool execution with consistent error handling.
    # Yields to the block and rescues any error, delegating to handle_mcp_error.
    # This eliminates duplicate rescue blocks across all tools.
    #
    # @param tool_name [String] Name of the tool for error reporting
    # @param error_mode [Symbol, String] Error handling mode (:off, :log, :debug)
    # @param output_chars [Symbol, String, nil] Output character mode for error messages
    def self.with_error_handling(tool_name, error_mode:, output_chars: :default)
      yield
    rescue => e
      handle_mcp_error(e, tool_name, error_mode: error_mode, output_chars: output_chars)
    end

    # Handle errors consistently across all MCP tools.
    # Returns an MCP::Tool::Response marked as an error (isError: true) so MCP
    # clients can programmatically detect the failure, with the user-friendly
    # message carried in the response content.
    #
    # @param error [Exception] The error to handle
    # @param tool_name [String] Name of the tool for error reporting
    # @param error_mode [Symbol, String] Error handling mode
    # @param output_chars [Symbol, String, nil] Output character mode for error messages
    # @return [MCP::Tool::Response] Error response (isError: true)
    def self.handle_mcp_error(error, tool_name, error_mode: :log, output_chars: :default)
      # Safely normalize error_mode to a symbol, defaulting to :log for invalid inputs
      # This prevents crashes when MCP clients send invalid types (null, numbers, objects, etc.)
      safe_mode = case error_mode
                  when Symbol then error_mode
                  when String then error_mode.to_sym
                  else :log
      end

      # Validate against VALID_ERROR_MODES and fallback to :log if invalid
      # This prevents ArgumentError when handling errors with invalid error_mode values
      safe_mode = :log unless ErrorHandler::VALID_ERROR_MODES.include?(safe_mode)

      # Create error handler with the specified mode
      error_handler = ErrorHandlerFactory.for_mcp_server(error_mode: safe_mode)

      # Normalize to a CovLoupe::Error so we can handle/log uniformly
      normalized = error.is_a?(CovLoupe::Error) \
        ? error : error_handler.convert_standard_error(error)
      log_mcp_error(normalized, tool_name, error_handler)

      # Convert error message to ASCII if needed
      error_message = normalized.user_friendly_message
      error_message = OutputChars.convert(error_message, output_chars || :default)
      # Flag the failure in the tool result via isError: true so MCP clients
      # can distinguish failed tool calls from successful ones, rather than
      # embedding error text in a normal success response. This is the
      # tool-result-level error signal; a JSON-RPC error is reserved for
      # protocol- or dispatch-level failures such as an unknown tool.
      ::MCP::Tool::Response.new(
        [{ 'type' => 'text', 'text' => "Error: #{error_message}" }],
        error: true
      )
    end

    # Respond with JSON as a resource to avoid clients mutating content types.
    # The resource embeds the JSON string with a clear MIME type.
    #
    # @param payload [Object] The data to serialize as JSON
    # @param name [String] Logical name for the JSON resource (informational)
    # @param pretty [Boolean] Use pretty formatting with indentation
    # @param output_chars [Symbol, String, nil] Output character mode (:default, :fancy, :ascii)
    # @return [MCP::Tool::Response] Response containing the JSON string
    def self.respond_json(payload, name: 'data.json', pretty: false, output_chars: :default)
      ascii_only = ascii_only?(output_chars)
      json = if pretty
        ascii_only ? JSON.pretty_generate(payload, ascii_only: true) : JSON.pretty_generate(payload)
      else
        ascii_only ? JSON.generate(payload, ascii_only: true) : JSON.generate(payload)
      end
      ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => json }])
    end

    # Determines if ASCII-only output is required based on the character mode setting.
    # Normalizes string inputs to symbols (MCP JSON provides strings, internal code uses symbols).
    # Uses strict validation to raise errors for invalid values.
    #
    # @param char_mode [Symbol, String, nil] The character mode (:default, :fancy, :ascii)
    # @return [Boolean] true if ASCII-only output is required
    # @raise [CovLoupe::UsageError] if char_mode is invalid
    def self.ascii_only?(char_mode)
      return false if char_mode.nil?

      normalized_mode_name = normalize_output_chars_strict(char_mode)
      OutputChars.ascii_mode?(normalized_mode_name)
    end
    private_class_method :ascii_only?

    def self.log_mcp_error(error, tool_name, error_handler)
      # Use the provided error handler for logging
      error_handler.send(:log_error, error, tool_name)
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

    # Creates and configures a CoverageModel instance.
    # Encapsulates the common pattern of merging config and initializing the model.
    # @param server_context [AppContext] The server context
    # @param model_option_overrides [Hash] Tool call parameters that override model defaults
    # @return [CoverageModel] The configured model
    def self.create_model(server_context:, **model_option_overrides)
      model, _config = create_configured_model(server_context: server_context,
        **model_option_overrides)
      model
    end

    # Creates and configures a CoverageModel instance, returning both the model and the configuration.
    # Useful when the tool needs access to the resolved configuration (e.g., root, raise_on_stale).
    #
    # Models are now lightweight (data is loaded lazily via ModelDataCache), so we create
    # a fresh instance on each call rather than caching at the model level.
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
      { root: '.', resultset: nil, raise_on_stale: false, tracked_globs: [] }
    end

    # Resolves output_chars from tool parameter or server context.
    # Tool parameter takes precedence over server context config.
    # Uses strict validation for tool parameters to catch invalid values.
    #
    # @param output_chars [String, Symbol, nil] Tool parameter value
    # @param server_context [AppContext] Server context with app_config
    # @return [Symbol] Normalized output_chars mode (:default, :fancy, or :ascii)
    # @raise [CovLoupe::UsageError] if output_chars parameter is invalid
    def self.resolve_output_chars(output_chars, server_context)
      # Use explicit parameter if provided
      return normalize_output_chars_strict(output_chars) if output_chars

      # Fall back to server context config
      server_context.app_config&.output_chars || :default
    end

    # Normalizes output_chars value with strict validation.
    # Converts string inputs to symbols and validates against allowed values.
    #
    # @param value [String, Symbol, nil] The output_chars value to normalize
    # @return [Symbol] Normalized output_chars mode (:default, :fancy, or :ascii)
    # @raise [CovLoupe::UsageError] if value is invalid
    def self.normalize_output_chars_strict(value)
      case value
      when Symbol then value
      when String
        begin
          OptionNormalizers.normalize_output_chars(value, strict: true)
        rescue OptionParser::InvalidArgument
          raise CovLoupe::UsageError, "Invalid output_chars value: #{value.inspect}. " \
            'Must be one of: default, fancy, ascii (or abbreviations: d, f, a)'
        end
      else
        raise CovLoupe::UsageError, "Invalid output_chars type: #{value.class.name}. " \
          'Must be a string (one of: default, fancy, ascii, or abbreviations: d, f, a)'
      end
    end
    private_class_method :normalize_output_chars_strict

    # Runs a file-based tool request by deriving payload method and JSON name from the tool class.
    # @param path [String] File path to analyze
    # @param error_mode [String] Error handling mode
    # @param output_chars [String, Symbol, nil] Output character mode
    # @param server_context [AppContext] Server context
    # @param model_option_overrides [Hash] Tool call parameters that override model defaults
    # @return [MCP::Tool::Response] JSON response
    def self.call_with_file_payload(path:, error_mode:, server_context:, output_chars: nil,
      **model_option_overrides)
      tool_name = name.split('::').last
      output_chars_sym = resolve_output_chars(output_chars, server_context)

      with_error_handling(tool_name, error_mode: error_mode, output_chars: output_chars_sym) do
        model, config = create_configured_model(server_context: server_context,
          **model_option_overrides)
        presenter = Presenters::CoveragePayloadPresenter.new(
          model:          model,
          path:           path,
          payload_method: payload_method_for(tool_name),
          raise_on_stale: config[:raise_on_stale]
        )
        respond_json(presenter.relativized_payload, name: json_name_for(tool_name), pretty: true,
          output_chars: output_chars_sym)
      end
    end

    # Infer CoverageModel method name from a tool class name.
    # CoverageSummaryTool -> :summary_for, CoverageRawTool -> :raw_for,
    # CoverageDetailedTool -> :detailed_for, UncoveredLinesTool -> :uncovered_for.
    def self.payload_method_for(tool_name)
      base = tool_name.sub(/Tool\z/, '')
      underscored = underscore(base)
        .sub(/\A(file_)?(coverage_)?/, '')
        .sub(/_lines\z/, '')
      :"#{underscored}_for"
    end

    # Infer the MCP JSON resource name from a tool class name.
    # CoverageSummaryTool -> coverage_summary.json, UncoveredLinesTool -> uncovered_lines.json.
    def self.json_name_for(tool_name)
      "#{underscore(tool_name.sub(/Tool\z/, ''))}.json"
    end

    # Minimal underscore helper to avoid pulling in ActiveSupport.
    def self.underscore(value)
      value
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
        .gsub(/([a-z\\d])([A-Z])/, '\\1_\\2')
        .downcase
    end
    private_class_method :payload_method_for, :json_name_for, :underscore
  end
end
