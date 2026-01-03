# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Presenters::ProjectCoveragePresenter do
  subject(:presenter) do
    described_class.new(
      model: model,
      sort_order: sort_order,
      raise_on_stale: raise_on_stale,
      tracked_globs: tracked_globs
    )
  end

  let(:model) { instance_double(CovLoupe::CoverageModel) }
  let(:sort_order) { :ascending }
  let(:raise_on_stale) { true }
  let(:tracked_globs) { ['lib/**/*.rb'] }
  let(:files) do
    [
      {
        'file' => '/abs/path/lib/foo.rb',
        'covered' => 5,
        'total' => 6,
        'percent_covered' => 83.33,
        'stale' => false
      },
      {
        'file' => '/abs/path/lib/bar.rb',
        'covered' => 1,
        'total' => 6,
        'percent_covered' => 16.67,
        'stale' => 'L'
      }
    ]
  end


  before do
    allow(model).to receive(:list).with(sort_order: sort_order, raise_on_stale: raise_on_stale,
      tracked_globs: tracked_globs).and_return({
        'files' => files,
        'skipped_files' => [
          { 'file' => '/abs/path/lib/skipped.rb', 'error' => 'boom' }
        ],
        'missing_tracked_files' => ['/abs/path/lib/missing.rb'],
        'newer_files' => [],
        'deleted_files' => ['/abs/path/lib/deleted.rb'],
        'length_mismatch_files' => ['/abs/path/lib/bad_length.rb'],
        'unreadable_files' => ['/abs/path/lib/unreadable.rb']
      })
    allow(model).to receive(:relativize) do |payload|
      relativizer = CovLoupe::PathRelativizer.new(
        root: '/abs/path',
        scalar_keys: %w[file file_path],
        array_keys: %w[
          newer_files
          missing_files
          deleted_files
          missing_tracked_files
          skipped_files
          length_mismatch_files
          unreadable_files
        ]
      )
      relativizer.relativize(payload)
    end
  end

  describe '#absolute_payload' do
    it 'returns files and counts with stale metadata' do
      payload = presenter.absolute_payload

      expect(payload['files']).to eq(files)
      expect(payload['counts']).to eq({ 'total' => 2, 'ok' => 1, 'stale' => 1 })
    end

    it 'memoizes the computed payload' do
      presenter.absolute_payload
      presenter.absolute_payload

      expect(model).to have_received(:list).once
    end
  end

  describe '#relativized_payload' do
    it 'relativizes the files list' do
      relativized = presenter.relativized_payload

      expect(relativized['files'].map { |f| f['file'] }).to eq(%w[lib/foo.rb lib/bar.rb])
    end
  end

  describe '#relative_files' do
    it 'returns the relativized file list' do
      expect(presenter.relative_files.map { |f| f['file'] }).to eq(%w[lib/foo.rb lib/bar.rb])
    end
  end

  describe '#relative_counts' do
    it 'returns the relativized counts hash' do
      expect(presenter.relative_counts).to eq({ 'total' => 2, 'ok' => 1, 'stale' => 1 })
    end
  end

  describe '#relative_skipped_files' do
    it 'returns the relativized skipped files' do
      expect(presenter.relative_skipped_files).to eq([
        { 'file' => 'lib/skipped.rb', 'error' => 'boom' }
      ])
    end
  end

  describe '#relative_missing_tracked_files' do
    it 'returns the relativized missing tracked files' do
      expect(presenter.relative_missing_tracked_files).to eq(['lib/missing.rb'])
    end
  end

  describe '#relative_newer_files' do
    it 'returns the relativized newer files' do
      expect(presenter.relative_newer_files).to eq([])
    end
  end

  describe '#relative_deleted_files' do
    it 'returns the relativized deleted files' do
      expect(presenter.relative_deleted_files).to eq(['lib/deleted.rb'])
    end
  end

  describe '#relative_length_mismatch_files' do
    it 'returns the relativized length mismatch files' do
      expect(presenter.relative_length_mismatch_files).to eq(['lib/bad_length.rb'])
    end
  end

  describe '#relative_unreadable_files' do
    it 'returns the relativized unreadable files' do
      expect(presenter.relative_unreadable_files).to eq(['lib/unreadable.rb'])
    end
  end
end
