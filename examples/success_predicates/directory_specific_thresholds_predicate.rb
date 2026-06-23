# frozen_string_literal: true

# Validation predicate: Different thresholds for different directories, using a `call` class method
# Usage: cov-loupe validate examples/success_predicates/directory_specific_thresholds_predicate.rb

class DirectorySpecificThresholds
  def self.call(model)
    new(model).call
  end

  def initialize(model)
    @files = model.relativize(model.list)['files']
  end

  def files_ok?(filemask, threshold_percentage)
    files = @files.select { |f| File.fnmatch?(filemask, f['file']) }
    files.all? { |f| f['percentage'] >= threshold_percentage }
  end

  def call
    [
      ['lib/api/*.rb',       85],
      ['lib/payments/*.rb',  60],
      ['lib/ops/jobs/*.rb',  80],
    ].map { |(filemask, threshold_pct)| files_ok?(filemask, threshold_pct) }
      .all?
  end
end

DirectorySpecificThresholds
