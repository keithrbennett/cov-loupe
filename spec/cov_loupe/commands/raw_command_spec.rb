# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::RawCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }
  let(:command) { described_class.new(cli_context) }

  before do
    cli_context.config.root = root
    cli_context.config.coverage_file = FIXTURE_PROJECT1_COVERAGE_PATH
    cli_context.config.format = :table
  end

  describe '#execute' do
    context 'with table format' do
      it 'prints the raw coverage lines for the requested file' do
        output = capture_command_output(command, %w[lib/foo.rb])

        expect(output).to include('│', 'lib/foo.rb', 'Line', 'Coverage')
      end
    end

    context 'when the file is fully covered' do
      it 'still prints the raw table' do
        mock_presenter(
          CovLoupe::Presenters::CoveragePayloadPresenter,
          absolute_payload: {
            'file'  => 'lib/perfect.rb',
            'lines' => [1, 1, 1],
            'stale' => 'ok',
          },
          relative_path:    'lib/perfect.rb'
        )

        output = capture_command_output(command, ['lib/perfect.rb'])

        expect(output).to include('│', '│    1 │        1 │')
        expect(output).not_to include('All lines covered!')
      end
    end

    context 'with JSON output' do
      before { cli_context.config.format = :json }

      it 'emits JSON with specific line data' do
        stub_staleness_check('length_mismatch') # Needed for stale data

        output = capture_command_output(command, ['lib/foo.rb'])

        payload = JSON.parse(output)
        expect(payload['file']).to eq('lib/foo.rb')
        expect(payload['lines']).to be_an(Array)
        expect(payload['lines'][2]).to eq(1) # specific value
        expect(payload['lines'][3]).to eq(0) # specific value
        expect(payload['stale']).to eq('length_mismatch')
      end
    end

    context 'with stale data (other formats)' do
      before { stub_staleness_check('length_mismatch') }

      # Use an array for expected_json_keys as we don't need exact value matching for these generic format tests
      it_behaves_like 'a command with formatted output', %w[lib/foo.rb], %w[file lines stale]
    end
  end
end
