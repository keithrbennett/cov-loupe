# frozen_string_literal: true

require_relative '../errors/errors'

module CovLoupe
  # Evaluates coverage predicates from either Ruby code strings or files.
  # Used by the validate subcommand, validate MCP tool, and library API.
  #
  # Security Warning:
  # Predicates execute as arbitrary Ruby code with full system privileges.
  # Only use predicates from trusted sources.
  class PredicateEvaluator
    # Evaluate a predicate from a code string
    #
    # @param code [String] Ruby code that returns a callable (lambda, proc, or object with #call)
    # @param model [CoverageModel] The coverage model to pass to the predicate
    # @return [Boolean] The result of calling the predicate with the model
    # @raise [PredicateError] If the code doesn't return a callable or has syntax errors
    def self.evaluate_code(code, model)
      guard_predicate_errors('code') do
        # WARNING: The predicate code executes with full Ruby privileges.
        # It has unrestricted access to the file system, network, and system commands.
        # Only use predicate code from trusted sources.
        #
        # We evaluate in a fresh Object context to prevent accidental access to
        # internals, but this provides NO security isolation.
        evaluation_context = Object.new
        predicate = evaluation_context.instance_eval(code, '<predicate>', 1)

        validate_callable(predicate)
        predicate.call(model)
      end
    end

    # Evaluate a predicate from a file
    #
    # @param path [String] Path to Ruby file containing predicate code
    # @param model [CoverageModel] The coverage model to pass to the predicate
    # @return [Boolean] The result of calling the predicate with the model
    # @raise [PredicateError] If the file doesn't exist, doesn't return a callable, or has syntax errors
    def self.evaluate_file(path, model)
      guard_predicate_errors('file') do
        unless File.exist?(path)
          raise PredicateError, "Predicate file not found: #{path}"
        end

        content = File.read(path)

        # WARNING: The predicate code executes with full Ruby privileges.
        # It has unrestricted access to the file system, network, and system commands.
        # Only use predicate files from trusted sources.
        #
        # We evaluate in a fresh Object context to prevent accidental access to
        # internals, but this provides NO security isolation.
        evaluation_context = Object.new
        predicate = evaluation_context.instance_eval(content, path, 1)

        validate_callable(predicate)
        predicate.call(model)
      end
    end

    # Runs the block, converting failures in the predicate itself into PredicateError.
    # Coverage-data and file errors raised by the model's own queries are runtime errors, not
    # predicate bugs, so they keep their type (and exit code). Anything else, including a
    # UsageError or ConfigurationError the predicate raises itself, is a problem in the
    # predicate, not in the command line.
    #
    # @param kind [String] 'code' or 'file', used in syntax error messages
    def self.guard_predicate_errors(kind)
      yield
    rescue SyntaxError => e
      raise PredicateError.new("Syntax error in predicate #{kind}: #{e.message}", e)
    rescue PredicateError, CoverageDataError, FileError
      raise
    rescue => e
      raise PredicateError.new(e.message, e)
    end
    private_class_method :guard_predicate_errors

    # Validate that an object is callable
    #
    # @param predicate [Object] The object to check
    # @raise [PredicateError] If the object doesn't respond to #call
    def self.validate_callable(predicate)
      unless predicate.respond_to?(:call)
        raise PredicateError, 'Predicate must be callable (lambda, proc, or object with #call method)'
      end
    end
    private_class_method :validate_callable
  end
end
