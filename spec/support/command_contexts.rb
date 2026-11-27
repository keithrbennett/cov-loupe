# frozen_string_literal: true

# A subcommand (the described class) run against the project1 fixture with table output.
RSpec.shared_context 'with a project1 command' do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }
  let(:command) { described_class.new(cli_context) }

  before do
    cli_context.config.root = root
    cli_context.config.coverage_file = FIXTURE_PROJECT1_COVERAGE_PATH
    cli_context.config.format = :table
    cli_context.config.source_mode = nil
  end
end
