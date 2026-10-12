# frozen_string_literal: true

require 'spec_helper'

# Files with no coverable lines (all-nil lines array) have a nil percentage;
# text output must show 'n/a' rather than raising.
RSpec.describe 'Path commands with a file that has no coverable lines' do
  let(:root) { (FIXTURES_DIR / 'project_no_coverable_lines').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }

  before do
    cli_context.config.root = root
    cli_context.config.coverage_file = File.join(root, 'coverage', 'coverage.json')
    cli_context.config.format = :table
    cli_context.config.source_mode = nil
  end

  {
    CovLoupe::Commands::UncoveredCommand => ['Coverage: n/a (0/0 lines)', 'No coverable lines.'],
    CovLoupe::Commands::DetailedCommand  => ['Coverage: 0/0 lines (n/a)', 'No coverable lines.'],
  }.each do |command_class, expected_lines|
    it "#{command_class.name.split('::').last} reports a file with no coverable lines" do
      output = capture_command_output(command_class.new(cli_context), ['lib/comments_only.rb'])

      expect(output).to include('File: lib/comments_only.rb', *expected_lines)
      expect(output).not_to include('All lines covered!', 'No data to display')
    end
  end
end
