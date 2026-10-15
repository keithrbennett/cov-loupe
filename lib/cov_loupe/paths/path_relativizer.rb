# frozen_string_literal: true

require 'pathname'
require_relative 'path_utils'

module CovLoupe
  # Utility object that converts configured path-bearing keys to forms
  # relative to a project root while leaving the original payload untouched.
  #
  # Operates on a deep copy of the payload to avoid mutating the caller's data.
  # Only keys listed in scalar_keys (single path) and array_keys (list of paths)
  # are relativized; all other values pass through unchanged.
  #
  # Example usage:
  #   relativizer = PathRelativizer.new(root: "/project", scalar_keys: ["file"], array_keys: ["files"])
  #   relativizer.relativize({ "file" => "/project/lib/foo.rb", "files" => ["/project/lib/bar.rb"] })
  #   # => { "file" => "lib/foo.rb", "files" => ["lib/bar.rb"] }
  #
  # @api private
  class PathRelativizer
    def initialize(root:, scalar_keys:, array_keys: [])
      @root = Pathname.new(PathUtils.expand(root || '.'))
      @scalar_keys = Array(scalar_keys).map(&:to_s).freeze
      @array_keys = Array(array_keys).map(&:to_s).freeze
    end

    def relativize(obj)
      deep_copy_and_relativize(obj)
    end

    # Converts an absolute path to a path relative to the root.
    # Falls back to the original path if conversion fails (e.g., different drive on Windows).
    #
    # @param path [String] file path (absolute or relative)
    # @return [String] relative path or original path on failure
    def relativize_path(path)
      # PathUtils handles all the complexity automatically
      PathUtils.relativize(path, @root.to_s)
    end

    private def deep_copy_and_relativize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), acc|
          acc[k] = relativize_value(k, v)
        end
      when Array
        obj.map { |item| deep_copy_and_relativize(item) }
      else
        obj
      end
    end

    private def relativize_value(key, value)
      key_str = key.to_s
      if @scalar_keys.include?(key_str) && value.is_a?(String)
        relativize_path(value)
      elsif @array_keys.include?(key_str) && value.is_a?(Array)
        value.map do |item|
          item.is_a?(String) ? relativize_path(item) : deep_copy_and_relativize(item)
        end
      else
        deep_copy_and_relativize(value)
      end
    end
  end
end
