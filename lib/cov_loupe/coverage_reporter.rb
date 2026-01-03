# frozen_string_literal: true

module CovLoupe
  # Reports files with coverage below a specified threshold.
  # Useful for displaying low coverage files after test runs.
  #
  # @example Basic usage in spec_helper.rb
  #   SimpleCov.at_exit do
  #     SimpleCov.result.format!
  #     report = CovLoupe::CoverageReporter.report(threshold: 80, count: 5)
  #     puts report if report
  #   end
  #
  module CoverageReporter
    module_function def report(threshold: 80, count: 5, model: nil)
      model ||= CoverageModel.new
      list_result = model.list(sort_order: :ascending)
      file_list = list_result['files']
        .select { |f| f['percent_covered'] < threshold }
        .first(count)
      file_list = model.relativize(file_list)

      return nil if file_list.empty?

      lines = ["\nLowest coverage files (< #{threshold}%):"]
      file_list.each do |f|
        lines << format('  %5.1f%%  %s', f['percent_covered'], f['file'])
      end
      lines.join("\n")
    end
  end
end
