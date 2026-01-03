# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::UncoveredCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }
  let(:command) { described_class.new(cli_context) }

  before do
    cli_context.config.root = root
    cli_context.config.resultset = FIXTURE_PROJECT1_RESULTSET_PATH
    cli_context.config.format = :table
    cli_context.config.source_mode = nil
  end

  describe '#execute' do
    context 'with table format' do
      it 'prints uncovered line numbers with the summary' do
        output = capture_command_output(command, ['lib/bar.rb'])

        expect(output).to include('│', 'lib/bar.rb', '33.33%')
      end
    end

    context 'when the file is fully covered' do
      before do
        mock_presenter(
          CovLoupe::Presenters::CoveragePayloadPresenter,
          absolute_payload: {
            'file' => 'lib/perfect.rb',
            'uncovered' => [],
            'summary' => { 'covered' => 10, 'total' => 10, 'percent_covered' => 100.0 }
          },
          relative_path: 'lib/perfect.rb'
        )
      end

      it 'prints a success message instead of a table' do
        output = capture_command_output(command, ['lib/perfect.rb'])

        expect(output).to include('All lines covered!', '100.00%')
        expect(output).not_to include('│')
      end
    end

    context 'with stale data' do
      before { stub_staleness_check('L') }

      it_behaves_like 'a command with formatted output', ['lib/foo.rb'],
        { 'file' => 'lib/foo.rb', 'uncovered' => [4], 'summary' => nil, 'stale' => 'L' }
    end
  end
end
