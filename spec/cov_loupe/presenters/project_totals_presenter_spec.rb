# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Presenters::ProjectTotalsPresenter do
  subject(:presenter) do
    described_class.new(
      model:          model,
      raise_on_stale: true,
      tracked_globs:  ['lib/**/*.rb']
    )
  end

  let(:model) { instance_double(CovLoupe::CoverageModel) }
  let(:raw_totals) do
    {
      'lines'            => {
        'total'      => 100,
        'covered'    => 80,
        'uncovered'  => 20,
        'percentage' => 80.0,
      },
      'tracking'         => {
        'enabled' => true,
        'globs'   => ['lib/**/*.rb'],
      },
      'files'            => {
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
            'missing_from_coverage' => 2,
            'unreadable'            => 0,
            'skipped'               => 0,
          },
        },
      },
      'timestamp_status' => 'ok',
    }
  end

  before do
    allow(model).to receive(:project_totals)
      .with(tracked_globs: ['lib/**/*.rb'], raise_on_stale: true)
      .and_return(raw_totals)
  end

  describe '#initialize' do
    it 'stores the model, raise_on_stale, and tracked_globs options' do
      expect(presenter.model).to eq(model)
      expect(presenter.raise_on_stale).to be(true)
      expect(presenter.tracked_globs).to eq(['lib/**/*.rb'])
    end
  end

  describe '#payload' do
    it 'returns project totals from the model' do
      result = presenter.payload

      expect(result).to include('lines', 'tracking', 'files')
      expect(result['lines']).to include(
        'total'      => 100,
        'covered'    => 80,
        'uncovered'  => 20,
        'percentage' => 80.0
      )
      expect(result['tracking']).to include('enabled' => true)
      expect(result['files']).to include('total' => 12)
    end

    it 'caches the result on subsequent calls' do
      presenter.payload
      presenter.payload

      expect(model).to have_received(:project_totals).once
    end

    it 'passes tracked_globs to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(tracked_globs: ['lib/**/*.rb'], raise_on_stale: true)
    end
  end

  context 'with raise_on_stale: false' do
    subject(:presenter) do
      described_class.new(
        model:          model,
        raise_on_stale: false,
        tracked_globs:  nil
      )
    end

    before do
      allow(model).to receive(:project_totals)
        .with(tracked_globs: nil, raise_on_stale: false)
        .and_return(raw_totals)
    end

    it 'passes raise_on_stale: false to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(tracked_globs: nil, raise_on_stale: false)
    end
  end

  context 'with empty tracked_globs' do
    subject(:presenter) do
      described_class.new(
        model:          model,
        raise_on_stale: true,
        tracked_globs:  []
      )
    end

    before do
      allow(model).to receive(:project_totals)
        .with(tracked_globs: [], raise_on_stale: true)
        .and_return(raw_totals)
    end

    it 'passes empty tracked_globs to the model' do
      presenter.payload

      expect(model).to have_received(:project_totals)
        .with(tracked_globs: [], raise_on_stale: true)
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
          .with(tracked_globs: ['lib/**/*.rb'], raise_on_stale: true)
          .and_return(raw_totals_missing_timestamps)
      end

      it 'returns "missing"' do
        expect(presenter.timestamp_status).to eq('missing')
      end
    end
  end
end
