# frozen_string_literal: true

module CovLoupe
  require_relative '../staleness/stale_status'

  # Reports files with coverage below a specified threshold.
  # Intended for use in spec_helper.rb (via SimpleCov.at_exit hook) to display
  # the worst-covered files after a test run.
  #
  # This is a convenience wrapper around CoverageModel — it does not add any
  # data processing beyond what the model provides.
  #
  # @example Basic usage in spec_helper.rb
  #   SimpleCov.at_exit do
  #     SimpleCov.result.format!
  #     report = CovLoupe::CoverageReporter.report(threshold: 80, count: 5)
  #     puts report if report
  #   end
  #
  # @example With custom coverage file path
  #   CovLoupe::CoverageReporter.report(
  #     threshold: 80,
  #     count: 5,
  #     coverage_file: 'custom/coverage/coverage.json'
  #   )
  #
  # @example With custom project root
  #   CovLoupe::CoverageReporter.report(
  #     threshold: 80,
  #     count: 5,
  #     root: '/path/to/project'
  #   )
  #
  # @api public
  module CoverageReporter
    module_function def report(threshold: 80, count: 5, model: nil, root: nil, coverage_file: nil)
      # Determine default root from SimpleCov if available
      root ||= defined?(SimpleCov) ? SimpleCov.root : '.'

      # Determine the default coverage directory from SimpleCov if available, under the
      # effective root so that an explicit root: also moves the coverage location
      default_coverage_file = (File.expand_path(SimpleCov.coverage_dir, root) if defined?(SimpleCov))

      model ||= CoverageModel.new(
        root:          root,
        coverage_file: coverage_file || default_coverage_file
      )
      list_result = model.list(sort_order: :ascending)
      file_list = list_result['files']
        .select { |f| f['percentage'] && f['percentage'] < threshold }
        .first(count)

      return nil if file_list.empty?

      lines = ["\nLowest coverage files (< #{threshold}%):"]
      file_list.each do |f|
        label = f['file']
        if StaleStatus.stale?(f['stale'])
          label = "#{label} (stale: #{f['stale']})"
        end
        lines << format('  %6.2f%%  %s', f['percentage'], label)
      end
      lines.join("\n")
    end
  end
end
