# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::UncoveredCommand do
  include_context 'with a project1 command'

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
          payload:       {
            'file' => 'lib/perfect.rb',
            'uncovered_lines' => [],
            'covered' => 10, 'total' => 10, 'percentage' => 100.0
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
      before { stub_staleness_check('length_mismatch') }

      it_behaves_like 'a command with formatted output', ['lib/foo.rb'],
        %w[file uncovered_lines uncovered percentage stale]
    end
  end
end
