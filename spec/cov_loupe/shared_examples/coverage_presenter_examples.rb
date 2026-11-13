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
  let(:stale_value) { config.fetch(:stale) }
  let(:raw_payload) { config.fetch(:payload).merge('stale' => stale_value) }

  before do
    allow(model).to receive(config.fetch(:model_method)).with(config.fetch(:path,
      'lib/foo.rb')).and_return(raw_payload)
  end

  describe '#payload' do
    it 'returns the model payload unchanged' do
      expect(presenter.payload).to eq(raw_payload)
    end

    it 'only fetches model data once across calls' do
      presenter.payload
      presenter.payload
      expect(model).to have_received(config.fetch(:model_method)).once
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
