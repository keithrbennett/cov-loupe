# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/scripts/latest_ci_status'

# rubocop:disable RSpec/SubjectStub
RSpec.describe CovLoupe::Scripts::LatestCiStatus do
  subject(:script) { described_class.new }

  describe '#call' do
    let(:branch) { 'main' }
    let(:run_list_args) do
      %w[gh run list --branch] + [branch] +
        %w[--limit 1 --json databaseId,status,conclusion,url,displayTitle,createdAt]
    end
    let(:run_json) do
      [
        {
          'databaseId'   => 123_456,
          'status'       => 'completed',
          'conclusion'   => 'success',
          'url'          => 'https://github.com/example/repo/actions/runs/123456',
          'displayTitle' => 'Test Run',
          'createdAt'    => '2023-10-27T10:00:00Z',
        },
      ].to_json
    end

    before do
      # Mock git branch detection
      allow(Open3).to receive(:capture3)
        .with(*%w[git rev-parse --abbrev-ref HEAD])
        .and_return([branch, '', instance_double(Process::Status, success?: true)])

      # Mock gh run list
      allow(Open3).to receive(:capture3)
        .with(*run_list_args)
        .and_return([run_json, '', instance_double(Process::Status, success?: true)])
    end

    it 'fetches and displays the latest CI run details' do
      _result, out, _err = capture_io { script.call }
      expect(out).to include('Fetching latest CI run')
      expect(out).to match(/Title:\s+Test Run/)
      expect(out).to match(/Status:.*SUCCESS/)
    end

    context 'when no runs are found' do
      let(:run_json) { '[]' }

      it 'notifies the user and exits gracefully' do
        _result, out, _err = capture_io { script.call }
        expect(out).to include("No workflow runs found for branch '#{branch}'.")
      end
    end

    context 'when the fetch command fails' do
      before do
        allow(Open3).to receive(:capture3)
          .with(*run_list_args)
          .and_return(['', 'error', instance_double(Process::Status, success?: false)])
      end

      it 'warns and exits with error code 1' do
        _result, _out, err = capture_io do
          expect { script.call }.to raise_error(SystemExit) do |e|
            expect(e.status).to eq(1)
          end
        end
        expect(err).to include(
          "Failed to fetch runs. Ensure 'gh' is installed and you are authenticated."
        )
      end
    end

    context 'when the run failed' do
      let(:run_json) do
        [
          {
            'databaseId'   => 654_321,
            'status'       => 'completed',
            'conclusion'   => 'failure',
            'url'          => 'url',
            'displayTitle' => 'Failed Run',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      before do
        allow(script).to receive(:system)
      end

      it 'attempts to fetch failure logs' do
        suppress_io { script.call }
        expect(script).to have_received(:system).with(*%w[gh run view 654321 --log-failed])
      end
    end

    context 'when the run is in progress' do
      let(:run_json) do
        [
          {
            'databaseId'   => 789_012,
            'status'       => 'in_progress',
            'conclusion'   => nil,
            'url'          => 'url',
            'displayTitle' => 'Running',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      it 'shows in-progress message with watch command' do
        _result, out, _err = capture_io { script.call }
        expect(out).to include('Build is currently running')
        expect(out).to include('gh run watch 789012')
      end
    end

    context 'when the run is queued' do
      let(:run_json) do
        [
          {
            'databaseId'   => 345_678,
            'status'       => 'queued',
            'conclusion'   => nil,
            'url'          => 'url',
            'displayTitle' => 'Queued',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      it 'shows queued message' do
        _result, out, _err = capture_io { script.call }
        expect(out).to include('Build is queued')
      end
    end

    context 'when the run was cancelled' do
      let(:run_json) do
        [
          {
            'databaseId'   => 111_222,
            'status'       => 'completed',
            'conclusion'   => 'cancelled',
            'url'          => 'url',
            'displayTitle' => 'Cancelled',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      it 'displays cancelled status with yellow color' do
        _result, out, _err = capture_io { script.call }
        expect(out).to match(/Status:.*CANCELLED/)
      end
    end

    context 'when the run has an unknown conclusion' do
      let(:run_json) do
        [
          {
            'databaseId'   => 999_888,
            'status'       => 'completed',
            'conclusion'   => 'unknown_status',
            'url'          => 'url',
            'displayTitle' => 'Unknown',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      it 'displays the status with default white color' do
        _result, out, _err = capture_io { script.call }
        expect(out).to match(/Status:.*UNKNOWN_STATUS/)
      end
    end

    context 'when the run is completed but conclusion is nil' do
      let(:run_json) do
        [
          {
            'databaseId'   => 777_666,
            'status'       => 'completed',
            'conclusion'   => nil,
            'url'          => 'url',
            'displayTitle' => 'Nil Conclusion',
            'createdAt'    => 'time',
          },
        ].to_json
      end

      it 'displays UNKNOWN status without crashing' do
        _result, out, _err = capture_io { script.call }
        expect(out).to match(/Status:.*UNKNOWN/)
      end
    end
  end
end
# rubocop:enable RSpec/SubjectStub
