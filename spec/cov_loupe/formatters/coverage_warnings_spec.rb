# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Formatters::CoverageWarnings do
  let(:path) { "lib/caf\u00e9\u2192.rb" }
  let(:skipped) { [{ 'file' => path, 'error' => "bad \u2018data\u2019" }] }
  let(:presenter) do
    instance_double(CovLoupe::Presenters::ProjectCoveragePresenter,
      relative_not_in_coverage_files: [], relative_newer_files: [path], relative_deleted_files: [],
      relative_length_mismatch_files: [], relative_unreadable_files: [],
      relative_skipped_files: skipped)
  end

  it 'lists excluded and skipped files with their paths and errors unchanged' do
    summary = described_class.exclusions_summary(presenter)

    expect(summary).to include("  - #{path}", "  - #{path}: bad \u2018data\u2019")
  end

  it 'shows skipped rows unchanged in the warning' do
    expect(described_class.skipped_rows_warning(presenter)).to include("  - #{path}: bad \u2018data\u2019")
  end

  describe '.payload_with_warnings' do
    [
      ['ok', nil, nil],
      ['missing', nil, described_class::TIMESTAMP_WARNING_LINES],
      ['ok', 'Root looks wrong', ['Root looks wrong']],
      ['missing', 'Root looks wrong', [*described_class::TIMESTAMP_WARNING_LINES, 'Root looks wrong']],
    ].each do |status, root_warning, expected|
      it "adds #{expected&.size || 'no'} warnings when timestamps are #{status}, " \
         "#{root_warning ? 'with' : 'without'} a root warning" do
        payload = { 'files' => [] }
        project_presenter = instance_double(CovLoupe::Presenters::ProjectTotalsPresenter,
          payload: payload, timestamp_status: status, root_warning: root_warning)

        result = described_class.payload_with_warnings(project_presenter)

        expect(result['warnings']).to eq(expected)
        expect(result).not_to be(payload)
        expect(payload).to eq('files' => [])
      end
    end
  end
end
