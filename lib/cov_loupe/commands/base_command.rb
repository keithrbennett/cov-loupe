# frozen_string_literal: true

require 'json'
require_relative '../formatters/formatters'
require_relative '../formatters/source_formatter'
require_relative '../model/model'
require_relative '../errors/errors'
require_relative '../output_chars'
require_relative '../payload_schema'

module CovLoupe
  module Commands
    # Base class for CLI subcommands. Provides shared behavior:
    # - Lazy model initialization via config.model_options
    # - Path-based argument handling with automatic error conversion
    # - Structured format output (JSON, YAML, etc.) with optional source code display
    # - Extra argument validation
    class BaseCommand
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

      # Convert text to ASCII if output_chars is :ascii
      protected def convert_text(text)
        OutputChars.convert(text, config.output_chars)
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

      protected def maybe_output_structured_format?(obj, model)
        return false if config.format == :table

        payload = PayloadSchema.add(model.relativize(obj))
        puts CovLoupe::Formatters.format(payload, config.format,
          output_chars: config.output_chars)
        true
      end

      protected def emit_structured_format_with_optional_source?(data, model, path)
        return false if config.format == :table

        payload = config.source_mode ? data.merge('source' => build_source_payload(model, path)) : data
        maybe_output_structured_format?(payload, model)
      end

      protected def build_source_payload(model, path)
        source_formatter.build_source_payload(model, path, mode: config.source_mode,
          context: config.source_context)
      end

      protected def print_source_for(model, path)
        formatted = source_formatter.format_source_for(model, path, mode: config.source_mode,
          context: config.source_context)
        puts formatted
      end
    end
  end
end
