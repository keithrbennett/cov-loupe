# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Presenters::ProjectCoveragePresenter do
  subject(:presenter) do
    described_class.new(
      model:          model,
      sort_order:     sort_order,
      raise_on_stale: raise_on_stale,
      tracked_globs:  tracked_globs
    )
  end

  let(:model) { instance_double(CovLoupe::CoverageModel) }
  let(:sort_order) { :ascending }
  let(:raise_on_stale) { true }
  let(:tracked_globs) { ['lib/**/*.rb'] }
  let(:files) do
    [
      {
        'file'       => 'lib/foo.rb',
        'covered'    => 5,
        'total'      => 6,
        'percentage' => 83.33,
        'stale'      => 'ok',
      },
      {
        'file'       => 'lib/bar.rb',
        'covered'    => 1,
        'total'      => 6,
        'percentage' => 16.67,
        'stale'      => 'length_mismatch',
      },
    ]
  end


  before do
    allow(model).to receive(:list).with(sort_order: sort_order, raise_on_stale: raise_on_stale,
      tracked_globs: tracked_globs).and_return({
        'files'                 => files,
        'skipped_files'         => [
          { 'file' => 'lib/skipped.rb', 'error' => 'boom' },
        ],
        'missing_tracked_files' => ['lib/missing.rb'],
        'newer_files'           => [],
        'deleted_files'         => ['lib/deleted.rb'],
        'length_mismatch_files' => ['lib/bad_length.rb'],
        'unreadable_files'      => ['lib/unreadable.rb'],
        'timestamp_status'      => 'ok',
      })
  end

  describe '#payload' do
    it 'returns files and counts with stale metadata' do
      payload = presenter.payload

      expect(payload['files']).to eq(files)
      expect(payload['counts']).to eq({ 'total' => 2, 'ok' => 1, 'stale' => 1 })
    end

    it 'includes timestamp_status in the payload' do
      payload = presenter.payload

      expect(payload['timestamp_status']).to eq('ok')
    end

    it 'memoizes the computed payload' do
      presenter.payload
      presenter.payload

      expect(model).to have_received(:list).once
    end
  end

  describe '#relative_files' do
    it 'returns the file list' do
      expect(presenter.relative_files.map { |f| f['file'] }).to eq(%w[lib/foo.rb lib/bar.rb])
    end
  end

  describe '#relative_counts' do
    it 'returns the counts hash' do
      expect(presenter.relative_counts).to eq({ 'total' => 2, 'ok' => 1, 'stale' => 1 })
    end
  end

  describe '#relative_skipped_files' do
    it 'returns the skipped files' do
      expect(presenter.relative_skipped_files).to eq([
        { 'file' => 'lib/skipped.rb', 'error' => 'boom' },
      ])
    end
  end

  describe '#relative_missing_tracked_files' do
    it 'returns the missing tracked files' do
      expect(presenter.relative_missing_tracked_files).to eq(['lib/missing.rb'])
    end
  end

  describe '#relative_newer_files' do
    it 'returns the newer files' do
      expect(presenter.relative_newer_files).to eq([])
    end
  end

  describe '#relative_deleted_files' do
    it 'returns the deleted files' do
      expect(presenter.relative_deleted_files).to eq(['lib/deleted.rb'])
    end
  end

  describe '#relative_length_mismatch_files' do
    it 'returns the length mismatch files' do
      expect(presenter.relative_length_mismatch_files).to eq(['lib/bad_length.rb'])
    end
  end

  describe '#relative_unreadable_files' do
    it 'returns the unreadable files' do
      expect(presenter.relative_unreadable_files).to eq(['lib/unreadable.rb'])
    end
  end

  describe '#timestamp_status' do
    it 'returns the timestamp status from the model' do
      expect(presenter.timestamp_status).to eq('ok')
    end

    context 'when timestamps are missing' do
      before do
        allow(model).to receive(:list).with(sort_order: sort_order, raise_on_stale: raise_on_stale,
          tracked_globs: tracked_globs).and_return({
            'files'                 => files,
            'skipped_files'         => [],
            'missing_tracked_files' => [],
            'newer_files'           => [],
            'deleted_files'         => [],
            'length_mismatch_files' => [],
            'unreadable_files'      => [],
            'timestamp_status'      => 'missing',
          })
      end

      it 'returns "missing"' do
        # Clear memoized payload
        presenter.instance_variable_set(:@payload, nil)
        expect(presenter.timestamp_status).to eq('missing')
      end
    end
  end
end
