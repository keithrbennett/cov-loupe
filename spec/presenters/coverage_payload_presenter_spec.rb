# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/coverage_presenter_examples'

RSpec.describe CovLoupe::Presenters::CoveragePayloadPresenter do
  [
    {
      name: 'summary payloads',
      payload_method: :summary_for,
      model_method: :summary_for,
      payload: {
        'file' => '/abs/path/lib/foo.rb',
        'summary' => { 'covered' => 8, 'total' => 10, 'percent_covered' => 80.0 }
      },
      stale: false,
      expected_keys: ['summary']
    },
    {
      name: 'raw payloads',
      payload_method: :raw_for,
      model_method: :raw_for,
      payload: {
        'file' => '/abs/path/lib/foo.rb',
        'lines' => [1, 0, nil, 2]
      },
      stale: 'L',
      expected_keys: ['lines']
    },
    {
      name: 'detailed payloads',
      payload_method: :detailed_for,
      model_method: :detailed_for,
      payload: {
        'file' => '/abs/path/lib/foo.rb',
        'lines' => [
          { 'line' => 1, 'hits' => 1, 'covered' => true },
          { 'line' => 2, 'hits' => 0, 'covered' => false }
        ],
        'summary' => { 'covered' => 1, 'total' => 2, 'percent_covered' => 50.0 }
      },
      stale: 'L',
      expected_keys: %w[lines summary]
    },
    {
      name: 'uncovered payloads',
      payload_method: :uncovered_for,
      model_method: :uncovered_for,
      payload: {
        'file' => '/abs/path/lib/foo.rb',
        'uncovered' => [2, 4],
        'summary' => { 'covered' => 2, 'total' => 4, 'percent_covered' => 50.0 }
      },
      stale: 'M',
      expected_keys: %w[uncovered summary]
    }
  ].each do |config|
    context "when building #{config.fetch(:name)}" do
      it_behaves_like 'a coverage presenter',
        config.merge(presenter_options: { payload_method: config.fetch(:payload_method) })
    end
  end

  describe CovLoupe::Presenters::PayloadCaching do
    it 'raises NotImplementedError when compute_absolute_payload is not implemented' do
      klass = Class.new do
        include CovLoupe::Presenters::PayloadCaching
      end

      instance = klass.new
      expect { instance.absolute_payload }.to raise_error(
        NotImplementedError,
        /must implement #compute_absolute_payload/
      )
    end
  end
end
