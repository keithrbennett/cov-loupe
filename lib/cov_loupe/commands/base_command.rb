# frozen_string_literal: true

require 'json'
require_relative '../formatters/formatters'
require_relative '../formatters/source_formatter'
require_relative '../model/model'
require_relative '../errors/errors'
require_relative '../payload_schema'

module CovLoupe
  module Commands
    # Base class for CLI subcommands. Provides shared behavior:
    # - Lazy model initialization via config.model_options
    # - Path-based argument handling with automatic error conversion
    # - Structured format output (JSON, YAML, etc.) with optional source code display
    # - Extra argument validation
    #
    # @api private
    class BaseCommand
      # Formats whose serializers cannot carry invalid UTF-8 in source lines.
      UTF8_ONLY_FORMATS = %i[json pretty_json yaml].freeze
      private_constant :UTF8_ONLY_FORMATS

      def initialize(cli_context)
        @cli = cli_context
        @config = cli_context.config
        @source_formatter = Formatters::SourceFormatter.new(
          **config.formatter_options
        )
      end

      attr_reader :cli, :config, :source_formatter

      protected def model
        @model ||= CoverageModel.new(**config.model_options)
      end

      # Formats a coverage percentage for text output; nil (no coverable lines) shows as 'n/a'.
      protected def format_percentage(percentage)
        percentage.nil? ? 'n/a' : format('%.2f%%', percentage)
      end

      protected def handle_with_path(args, name)
        path = args.shift or raise UsageError.for_subcommand("#{name} <path>")
        reject_extra_args(args, name)
        yield(path)
      rescue Errno::ENOENT
        raise FileNotFoundError, "File not found: #{path}"
      rescue Errno::EACCES
        raise FilePermissionError, "Permission denied: #{path}"
      end

      # Validates that no unexpected arguments remain after parsing.
      # Raises UsageError if extra args are present.
      protected def reject_extra_args(args, command_name)
        return if args.empty?

        extra = args.join(' ')
        raise UsageError, "Unexpected argument(s) for '#{command_name}': #{extra}"
      end

      protected def maybe_output_structured_format?(obj)
        return false if config.format == :table

        puts CovLoupe::Formatters.format(PayloadSchema.add(obj), config.format,
          output_chars: config.output_chars)
        true
      end

      protected def emit_structured_format_with_optional_source?(data, model, path)
        return false if config.format == :table

        payload = config.source_mode ? data.merge('source' => build_source_payload(model, path)) : data
        maybe_output_structured_format?(payload)
      end

      protected def build_source_payload(model, path)
        source_formatter.build_source_payload(model, path, mode: config.source_mode,
          context: config.source_context, require_utf8: UTF8_ONLY_FORMATS.include?(config.format))
      end

      protected def print_source_for(model, path)
        formatted = source_formatter.format_source_for(model, path, mode: config.source_mode,
          context: config.source_context)
        puts formatted
      end
    end
  end
end
