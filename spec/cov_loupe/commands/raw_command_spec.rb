# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::RawCommand do
  include_context 'with a project1 command'

  describe '#execute' do
    context 'with table format' do
      it 'prints the raw coverage lines for the requested file' do
        output = capture_command_output(command, %w[lib/foo.rb])

        expect(output).to include('│', 'lib/foo.rb', 'Line', 'Hits')
      end
    end

    context 'when the file is fully covered' do
      it 'still prints the raw table' do
        mock_presenter(
          CovLoupe::Presenters::CoveragePayloadPresenter,
          payload:       {
            'file'      => 'lib/perfect.rb',
            'line_hits' => [1, 1, 1],
            'stale'     => 'ok',
          },
          relative_path: 'lib/perfect.rb'
        )

        output = capture_command_output(command, ['lib/perfect.rb'])

        expect(output).to include('│', '│    1 │    1 │')
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
        expect(payload['line_hits']).to be_an(Array)
        expect(payload['line_hits'][2]).to eq(1) # specific value
        expect(payload['line_hits'][3]).to eq(0) # specific value
        expect(payload['stale']).to eq('length_mismatch')
      end
    end

    context 'with source_mode set' do
      before { cli_context.config.source_mode = :full }

      it 'ignores it in table output' do
        with_source = capture_command_output(command, %w[lib/foo.rb])
        cli_context.config.source_mode = nil

        expect(with_source).to eq(capture_command_output(command, %w[lib/foo.rb]))
      end

      it 'does not embed source in structured output' do
        cli_context.config.format = :json

        expect(JSON.parse(capture_command_output(command, %w[lib/foo.rb]))).not_to have_key('source')
      end
    end

    context 'with stale data (other formats)' do
      before { stub_staleness_check('length_mismatch') }

      # Use an array for expected_json_keys as we don't need exact value matching for these generic format tests
      it_behaves_like 'a command with formatted output', %w[lib/foo.rb], %w[file line_hits stale]
    end
  end
end
