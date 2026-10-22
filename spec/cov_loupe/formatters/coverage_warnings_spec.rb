# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Formatters::CoverageWarnings do
  let(:path) { "lib/caf\u00e9\u2192.rb" }
  let(:skipped) { [{ 'file' => path, 'error' => "bad \u2018data\u2019" }] }
  let(:presenter) do
    instance_double(CovLoupe::Presenters::ProjectCoveragePresenter,
      relative_missing_tracked_files: [], relative_newer_files: [path], relative_deleted_files: [],
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
end
