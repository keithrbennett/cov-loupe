# frozen_string_literal: true

module CovLoupe
  require_relative '../deprecation'
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
  module CoverageReporter
    module_function def report(threshold: 80, count: 5, model: nil, root: nil,
      coverage_file: nil, resultset: nil)
      if resultset && !coverage_file
        Deprecation.warn('CoverageReporter.report(resultset:)', 'coverage_file:')
        coverage_file = resultset
      end

      # Determine default root from SimpleCov if available
      default_root = defined?(SimpleCov) ? SimpleCov.root : '.'

      # Determine the default coverage file from SimpleCov if available. The
      # coverage directory is passed rather than a specific filename so the
      # resolver applies its usual preference for coverage.json.
      default_coverage_file = if defined?(SimpleCov)
        File.join(SimpleCov.root, SimpleCov.coverage_dir)
      end

      model ||= CoverageModel.new(
        root:          root || default_root,
        coverage_file: coverage_file || default_coverage_file
      )
      list_result = model.list(sort_order: :ascending)
      file_list = list_result['files']
        .select { |f| f['percentage'] && f['percentage'] < threshold }
        .first(count)
      file_list = model.relativize(file_list)

      return nil if file_list.empty?

      lines = ["\nLowest coverage files (< #{threshold}%):"]
      file_list.each do |f|
        label = f['file']
        if StaleStatus.stale?(f['stale'])
          label = "#{label} (stale: #{f['stale']})"
        end
        lines << format('  %5.1f%%  %s', f['percentage'], label)
      end
      lines.join("\n")
    end
  end
end
