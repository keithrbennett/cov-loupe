# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/coverage_presenter_examples'

RSpec.describe CovLoupe::Presenters::CoveragePayloadPresenter do
  [
    {
      name:           'summary payloads',
      payload_method: :summary_for,
      model_method:   :summary_for,
      payload:        {
        'file'    => 'lib/foo.rb',
        'covered' => 8, 'uncovered' => 2, 'total' => 10, 'percentage' => 80.0
      },
      stale:          'ok',
    },
    {
      name:           'raw payloads',
      payload_method: :raw_for,
      model_method:   :raw_for,
      payload:        {
        'file'      => 'lib/foo.rb',
        'line_hits' => [1, 0, nil, 2],
      },
      stale:          'length_mismatch',
    },
    {
      name:           'detailed payloads',
      payload_method: :detailed_for,
      model_method:   :detailed_for,
      payload:        {
        'file'    => 'lib/foo.rb',
        'lines'   => [
          { 'line' => 1, 'hits' => 1, 'covered' => true },
          { 'line' => 2, 'hits' => 0, 'covered' => false },
        ],
        'covered' => 1, 'uncovered' => 1, 'total' => 2, 'percentage' => 50.0
      },
      stale:          'length_mismatch',
    },
    {
      name:           'uncovered payloads',
      payload_method: :uncovered_for,
      model_method:   :uncovered_for,
      payload:        {
        'file' => 'lib/foo.rb',
        'uncovered_lines' => [2, 4],
        'covered' => 2, 'uncovered' => 2, 'total' => 4, 'percentage' => 50.0
      },
      stale:          'deleted',
    },
  ].each do |config|
    context "when building #{config.fetch(:name)}" do
      it_behaves_like 'a coverage presenter',
        config.merge(presenter_options: { payload_method: config.fetch(:payload_method) })
    end
  end

  describe CovLoupe::Presenters::PayloadCaching do
    it 'raises NotImplementedError when compute_payload is not implemented' do
      klass = Class.new do
        include CovLoupe::Presenters::PayloadCaching
      end

      instance = klass.new
      expect { instance.payload }.to raise_error(
        NotImplementedError,
        /must implement #compute_payload/
      )
    end
  end
end
