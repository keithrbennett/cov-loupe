# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Presenters::ProjectTotalsPresenter do
  subject(:presenter) do
    described_class.new(
      model:          model,
      raise_on_stale: true,
      file_globs:     ['lib/**/*.rb']
    )
  end

  let(:model) { instance_double(CovLoupe::CoverageModel) }
  let(:raw_totals) do
    {
      'total'            => 100,
      'covered'          => 80,
      'uncovered'        => 20,
      'percentage'       => 80.0,
      'file_globs'       => ['lib/**/*.rb'],
      'file_counts'      => {
        'total'            => 12,
        'with_coverage'    => {
          'total' => 10,
          'ok'    => 9,
          'stale' => {
            'total'   => 1,
            'by_type' => {
              'deleted'         => 0,
              'newer'           => 1,
              'length_mismatch' => 0,
              'unreadable'      => 0,
            },
          },
        },
        'without_coverage' => {
          'total'   => 2,
          'by_type' => {
            'not_in_coverage' => 2,
            'skipped'         => 0,
          },
        },
      },
      'timestamp_status' => 'ok',
    }
  end

  before do
    allow(model).to receive(:project_totals)
      .with(file_globs: ['lib/**/*.rb'], raise_on_stale: true)
      .and_return(raw_totals)
  end

  describe '#initialize' do
    it 'stores the model, raise_on_stale, and file_globs options' do
      expect(presenter.model).to eq(model)
      expect(presenter.raise_on_stale).to be(true)
      expect(presenter.file_globs).to eq(['lib/**/*.rb'])
    end
  end

  describe '#payload' do
    it 'returns project totals from the model' do
      expect(presenter.payload).to eq(raw_totals)
    end

    it 'caches the result on subsequent calls' do
      presenter.payload
      presenter.payload

      expect(model).to have_received(:project_totals).once
    end

    it 'passes file_globs to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(file_globs: ['lib/**/*.rb'], raise_on_stale: true)
    end
  end

  context 'with raise_on_stale: false' do
    subject(:presenter) do
      described_class.new(
        model:          model,
        raise_on_stale: false,
        file_globs:     nil
      )
    end

    before do
      allow(model).to receive(:project_totals)
        .with(file_globs: nil, raise_on_stale: false)
        .and_return(raw_totals)
    end

    it 'passes raise_on_stale: false to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(file_globs: nil, raise_on_stale: false)
    end
  end

  context 'with empty file_globs' do
    subject(:presenter) do
      described_class.new(
        model:          model,
        raise_on_stale: true,
        file_globs:     []
      )
    end

    before do
      allow(model).to receive(:project_totals)
        .with(file_globs: [], raise_on_stale: true)
        .and_return(raw_totals)
    end

    it 'passes empty file_globs to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(file_globs: [], raise_on_stale: true)
    end
  end

  describe '#timestamp_status' do
    it 'returns the timestamp status from the payload' do
      expect(presenter.timestamp_status).to eq('ok')
    end

    context 'when timestamps are missing' do
      let(:raw_totals_missing_timestamps) do
        raw_totals.merge('timestamp_status' => 'missing')
      end

      before do
        allow(model).to receive(:project_totals)
          .with(file_globs: ['lib/**/*.rb'], raise_on_stale: true)
          .and_return(raw_totals_missing_timestamps)
      end

      it 'returns "missing"' do
        expect(presenter.timestamp_status).to eq('missing')
      end
    end
  end
end
