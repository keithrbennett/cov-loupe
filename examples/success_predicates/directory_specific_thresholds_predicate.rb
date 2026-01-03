# frozen_string_literal: true

# Success predicate: Different thresholds for different directories, using a `call` class method
# Usage: cov-loupe --success-predicate examples/success_predicates/directory_specific_thresholds_predicate.rb

class DirectorySpecificThresholds
  def self.call(model)
    new(model).call
  end

  def initialize(model)
    @files = model.relativize(model.list)
  end

  def files_ok?(filemask, threshold_percentage)
    files = @files.select { |f| File.fnmatch?(filemask, f['file']) }
    files.all? { |f| f['percent_covered'] >= threshold_percentage }
  end

  def call
    [
      ['lib/cov_loupe/**/*.rb',                 85], # global default minimum
      ['lib/cov_loupe/option_parsers/**/*.rb',  95],
      ['lib/cov_loupe/tools/**/*.rb',          100]
    ].map { |(filemask, threshold_pct)| files_ok?(filemask, threshold_pct) }
      .all?
  end
end

DirectorySpecificThresholds
