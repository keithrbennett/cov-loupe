# frozen_string_literal: true

# Validation predicate: All files must have >= 80% coverage, illustrates use of a class `call` method
# Usage: cov-loupe validate examples/success_predicates/all_files_above_threshold_predicate.rb
class AllFilesAboveThreshold
  THRESHOLD = 80

  def self.call(model)
    low_files = model.list['files'].select { |f| f['percentage'] < THRESHOLD }

    if low_files.any?
      # Can add custom logging/reporting here
      warn "Files below #{THRESHOLD}%:"
      low_files.each { |f| warn format('%5.1f%%  %s', f['percentage'], f['file']) }
    end

    low_files.none?
  end
end

AllFilesAboveThreshold
