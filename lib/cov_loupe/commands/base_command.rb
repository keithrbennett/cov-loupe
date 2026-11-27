# frozen_string_literal: true

require 'json'
require_relative '../formatters/formatters'
require_relative '../formatters/source_formatter'
require_relative '../model/model'
require_relative '../errors/errors'
require_relative '../payload_schema'
require_relative '../presenters/coverage_payload_presenter'
require_relative '../formatters/table_formatter'

module CovLoupe
  module Commands
    # Base class for CLI subcommands. Provides shared behavior:
    # - Lazy model initialization via config.model_options
    # - Path-based argument handling with automatic error conversion
    # - Single-file payload commands (with_file_payload) and their shared table output
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

      # Prints each warning text that is not empty to stderr.
      protected def warn_nonempty(*texts)
        texts.each { |text| warn text unless text.empty? }
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

      # Runs a single-file subcommand: reads the path argument and fetches the payload with
      # payload_method. A structured format is emitted directly, with source when the command
      # supports it; for table output, the block receives the payload and the project-relative
      # path, and the source follows when requested.
      protected def with_file_payload(args, name, payload_method, source: true)
        handle_with_path(args, name) do |path|
          presenter = Presenters::CoveragePayloadPresenter.new(model: model, path: path,
            payload_method: payload_method)
          data = presenter.payload
          next if emit_structured_format?(data, path, source: source)

          yield data, presenter.relative_path
          print_source_for(path) if source && config.source_mode
        end
      end

      # Prints the "File:" and "Coverage:" heading lines of a single-file table output.
      protected def print_coverage_heading(relative_path, data)
        puts "File: #{relative_path}"
        puts "Coverage: #{format_percentage(data['percentage'])} " \
             "(#{data['covered']}/#{data['total']} lines)"
      end

      protected def print_table(headers, rows, alignments)
        puts TableFormatter.format(
          headers:      headers,
          rows:         rows,
          alignments:   alignments,
          output_chars: config.output_chars
        )
      end

      private def emit_structured_format?(data, path, source:)
        return false if config.format == :table

        payload = source && config.source_mode ? data.merge('source' => build_source_payload(path)) : data
        maybe_output_structured_format?(payload)
      end

      private def build_source_payload(path)
        source_formatter.build_source_payload(model, path, mode: config.source_mode,
          context: config.source_context, require_utf8: UTF8_ONLY_FORMATS.include?(config.format))
      end

      private def print_source_for(path)
        puts source_formatter.format_source_for(model, path, mode: config.source_mode,
          context: config.source_context)
      end
    end
  end
end
