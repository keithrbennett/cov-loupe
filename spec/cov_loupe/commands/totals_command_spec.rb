# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::TotalsCommand do
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
      it 'prints aggregated totals for the project' do
        output = capture_command_output(command, [])

        expect(output).to include('Tracked globs:', 'Lines', '50.00%')
      end

      it 'omits without coverage breakdown when tracking is disabled' do
        # Disable tracked globs to ensure tracking is off
        cli_context.config.tracked_globs = []
        output = capture_command_output(command, [])

        expect(output).to include('Tracked globs: (tracking disabled)')
        expect(output).not_to include('Without coverage')
      end

      it 'shows file breakdown with stale and without coverage details' do
        # Mock the presenter to return data with stale and without coverage counts
        presenter_double = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
        allow(presenter_double).to receive_messages(
          absolute_payload: {
            'lines'    => {
              'total'          => 6,
              'covered'        => 3,
              'uncovered'      => 3,
              'percentage'     => 50.0,
              'included_files' => 2,
              'excluded_files' => 1,
            },
            'tracking' => {
              'enabled' => true,
              'globs'   => ['lib/**/*.rb'],
            },
            'files'    => {
              'total'            => 4,
              'with_coverage'    => {
                'total' => 3,
                'ok'    => 2,
                'stale' => {
                  'total'   => 1,
                  'by_type' => {
                    'missing_from_disk' => 0,
                    'newer'             => 1,
                    'length_mismatch'   => 0,
                    'unreadable'        => 0,
                  },
                },
              },
              'without_coverage' => {
                'total'   => 1,
                'by_type' => {
                  'missing_from_coverage' => 1,
                  'unreadable'            => 0,
                  'skipped'               => 0,
                },
              },
            },
          },
          timestamp_status: 'ok'
        )
        allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new)
          .and_return(presenter_double)

        output = capture_command_output(command, [])

        aggregate_failures do
          expect(output).to include('File breakdown:')
          expect(output).to include('With coverage: 3 total, 2 ok, 1 stale')
          expect(output).to include('newer than coverage = 1')
          expect(output).to include('Without coverage: 1 total')
          expect(output).to include('Missing from coverage = 1')
        end
      end

      it 'handles nil percentage gracefully' do
        presenter_double = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
        allow(presenter_double).to receive_messages(
          absolute_payload: {
            'lines'    => { 'total' => 0, 'covered' => 0, 'uncovered' => 0, 'percentage' => nil,
                         'included_files' => 0, 'excluded_files' => 0 },
            'tracking' => { 'enabled' => false, 'globs' => [] },
            'files'    => { 'total'         => 0,
                            'with_coverage' => { 'total' => 0, 'ok' => 0,
                                              'stale' => { 'total' => 0, 'by_type' => {} } } },
          },
          timestamp_status: 'ok'
        )
        allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new).and_return(presenter_double)

        output = capture_command_output(command, [])

        expect(output).to include('n/a')
      end
    end

    it_behaves_like 'a command with formatted output', [], %w[lines tracking files]

    it 'raises when unexpected arguments are provided' do
      expect do
        command.execute(%w[extra])
      end.to raise_error(CovLoupe::UsageError, include('totals'))
    end

    shared_examples 'timestamp warning display' do |timestamp_status, should_warn|
      let(:base_payload) do
        {
          'lines'    => { 'total' => 0, 'covered' => 0, 'uncovered' => 0, 'percentage' => 0,
                       'included_files' => 0, 'excluded_files' => 0 },
          'tracking' => { 'enabled' => false, 'globs' => [] },
          'files'    => {
            'total'         => 0,
            'with_coverage' => {
              'total' => 0,
              'ok'    => 0,
              'stale' => {
                'total'   => 0,
                'by_type' => {
                  'missing_from_disk' => 0,
                  'newer'             => 0,
                  'length_mismatch'   => 0,
                  'unreadable'        => 0,
                },
              },
            },
          },
        }
      end

      before do
        payload = base_payload.merge('timestamp_status' => timestamp_status)
        presenter_double = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter)
        allow(presenter_double).to receive_messages(
          absolute_payload: payload,
          timestamp_status: timestamp_status
        )
        allow(CovLoupe::Presenters::ProjectTotalsPresenter).to receive(:new)
          .and_return(presenter_double)
      end

      it "#{should_warn ? 'displays' : 'does not display'} a warning about missing timestamps" do
        _result, _out, stderr_output = capture_io { command.execute([]) }

        if should_warn
          expect(stderr_output).to include(
            'WARNING: Coverage timestamps are missing',
            'Time-based staleness checks were skipped'
          )
        else
          expect(stderr_output).not_to include('WARNING: Coverage timestamps are missing')
        end
      end
    end

    context 'when timestamp_status is missing' do
      it_behaves_like 'timestamp warning display', 'missing', true
    end

    context 'when timestamp_status is ok' do
      it_behaves_like 'timestamp warning display', 'ok', false
    end
  end
end
