# frozen_string_literal: true

RSpec.shared_examples 'a coverage presenter' do |config|
  subject(:presenter) do
    described_class.new(
      model: model,
      path:  config.fetch(:path, 'lib/foo.rb'),
      **config.fetch(:presenter_options, {})
    )
  end

  let(:model) { instance_double(CovLoupe::CoverageModel) }
  let(:raw_payload) { config.fetch(:payload) }
  let(:stale_value) { config.fetch(:stale) }

  before do
    allow(model).to receive(config.fetch(:model_method)).with(config.fetch(:path,
      'lib/foo.rb')).and_return(raw_payload)
    allow(model).to receive(:staleness_for).with(config.fetch(:path,
      'lib/foo.rb')).and_return(stale_value)
  end

  describe '#payload' do
    it 'returns data with stale metadata' do
      result = presenter.payload

      expect(result).to include('file' => raw_payload['file'])
      Array(config.fetch(:expected_keys)).each do |key|
        expect(result).to include(key => raw_payload[key])
      end
      expect(result['stale']).to eq(stale_value)
    end

    it 'does not mutate the underlying model data' do
      presenter.payload
      expect(raw_payload).not_to have_key('stale')
    end

    it 'only fetches model data once across calls' do
      presenter.payload
      presenter.payload
      expect(model).to have_received(config.fetch(:model_method)).once
      expect(model).to have_received(:staleness_for).once
    end
  end

  describe '#relative_path' do
    it 'returns the file path from the model payload' do
      expect(presenter.relative_path).to eq(raw_payload['file'])
    end
  end

  describe '#stale' do
    it 'returns the cached staleness flag' do
      expect(presenter.stale).to eq(stale_value)
      presenter.payload
      expect(presenter.stale).to eq(stale_value)
    end
  end
end
