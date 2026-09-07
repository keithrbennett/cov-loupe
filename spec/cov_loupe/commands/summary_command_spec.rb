# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::SummaryCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }
  let(:command) { described_class.new(cli_context) }

  before do
    cli_context.config.root = root
    cli_context.config.coverage_file = FIXTURE_PROJECT1_COVERAGE_PATH
    cli_context.config.format = :table
    cli_context.config.source_mode = nil
  end

  describe '#execute' do
    context 'with table format' do
      it 'prints a coverage summary line with a relative path' do
        output = capture_command_output(command, ['lib/foo.rb'])

        expect(output).to include('│', '66.67%', 'lib/foo.rb')
      end

      it 'marks stale files with a Yes indicator' do
        stub_staleness_check('length_mismatch')

        output = capture_command_output(command, ['lib/foo.rb'])

        expect(output).to include('Yes')
      end

      it 'prints source when source_mode is enabled' do
        cli_context.config.source_mode = :full

        output = capture_command_output(command, ['lib/foo.rb'])

        expect(output).to show_source_table_or_fallback
      end

      it 'handles nil percentage gracefully' do
        # Stub the presenter to return nil percentage
        presenter_double = instance_double(CovLoupe::Presenters::CoveragePayloadPresenter)
        allow(presenter_double).to receive_messages(
          absolute_payload: {
            'file'    => 'lib/empty.rb',
            'summary' => { 'covered' => 0, 'total' => 0, 'percentage' => nil },
            'stale'   => 'ok',
          },
          relative_path:    'lib/empty.rb'
        )
        allow(CovLoupe::Presenters::CoveragePayloadPresenter).to receive(:new).and_return(presenter_double)

        output = capture_command_output(command, ['lib/empty.rb'])

        expect(output).to include('n/a')
      end
    end

    context 'with structured format and source data' do
      before do
        cli_context.config.format = :json
        cli_context.config.source_mode = :full
      end

      it 'embeds source payload in structured output' do
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
        %w[file summary stale]
    end

    it 'rejects extra arguments after path' do
      expect do
        command.execute(['lib/foo.rb', 'extra', 'args'])
      end.to raise_error(CovLoupe::UsageError, /Unexpected argument.*extra args/)
    end
  end
end
