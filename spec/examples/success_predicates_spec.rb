# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'examples/success_predicates' do
  def evaluate(filename, model)
    path = File.expand_path("../../examples/success_predicates/#{filename}", __dir__)
    result = nil
    suppress_io { result = CovLoupe::PredicateEvaluator.evaluate_file(path, model) }
    result
  end

  def fixture_model(project)
    root = (FIXTURES_DIR / project).to_s
    CovLoupe::CoverageModel.new(root: root,
      coverage_file: File.join(root, 'coverage', 'coverage.json'))
  end

  # project1 has a 33% file and 50% total coverage and no files under the directory masks.
  # project_no_coverable_lines has only nil percentages, including lib/api/comments_only.rb under
  # a directory mask: per-file checks skip such files, and project-total checks fail on a nil total.
  {
    'all_files_above_threshold_predicate.rb'     => { project1: false, project_no_coverable_lines: true },
    'project_coverage_minimum_predicate.rb'      => { project1: false, project_no_coverable_lines: false },
    'directory_specific_thresholds_predicate.rb' => { project1: true,  project_no_coverable_lines: true },
  }.each do |filename, expectations|
    expectations.each do |project, expected|
      it "#{filename} returns #{expected} for #{project}" do
        expect(evaluate(filename, fixture_model(project.to_s))).to be(expected)
      end
    end
  end

  # Both thresholds involved are 85%, so one boundary table drives both stubbed-model checks.
  { 84.9 => false, 85.0 => true }.each do |percentage, expected|
    it "project_coverage_minimum_predicate.rb returns #{expected} for a #{percentage}% project total" do
      model = instance_double(CovLoupe::CoverageModel,
        project_totals: { 'lines' => { 'percentage' => percentage } })

      expect(evaluate('project_coverage_minimum_predicate.rb', model)).to be(expected)
    end

    it "directory_specific_thresholds_predicate.rb returns #{expected} for a #{percentage}% API file" do
      files = [
        { 'file' => 'lib/api/empty.rb', 'percentage' => nil },
        { 'file' => 'lib/api/client.rb', 'percentage' => percentage },
      ]
      model = instance_double(CovLoupe::CoverageModel, list: { 'files' => files })

      expect(evaluate('directory_specific_thresholds_predicate.rb', model)).to be(expected)
    end
  end
end
