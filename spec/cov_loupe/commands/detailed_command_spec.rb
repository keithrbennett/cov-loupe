# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::DetailedCommand do
  include_context 'with a project1 command'

  describe '#execute' do
    context 'with table format' do
      it 'prints the detailed coverage table' do
        output = capture_command_output(command, ['lib/foo.rb'])

        expect(output).to include('File: lib/foo.rb', 'Coverage: 66.66% (2/3 lines)', 'Line', 'Covered')
      end

      it 'prints annotated source when source_mode is enabled' do
        cli_context.config.source_mode = :full

        output = capture_command_output(command, ['lib/foo.rb'])

        expect(output).to show_source_table_or_fallback
      end

      it 'prints stale status when data is stale' do
        stub_staleness_check('length_mismatch')
        output = capture_command_output(command, ['lib/foo.rb'])
        expect(output).to include('Stale: length_mismatch')
      end
    end

    context 'with structured format and source output' do
      before do
        cli_context.config.format = :json
        cli_context.config.source_mode = :full
      end

      it 'embeds the source payload in structured output' do
        output = capture_command_output(command, ['lib/foo.rb'])
        payload = JSON.parse(output)

        expect(payload).to include('source')
        expect(payload['source']).to be_an(Array)
        expect(payload['source'].map { |row| row['line'] }).to include(1, 6)
      end
    end

    context 'with stale data' do
      before { stub_staleness_check('length_mismatch') }

      it_behaves_like 'a command with formatted output', ['lib/foo.rb'],
        { 'file' => 'lib/foo.rb', 'lines' => nil, 'percentage' => nil, 'stale' => 'length_mismatch' }
    end
  end
end
