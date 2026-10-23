# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::PredicateEvaluator do
  describe '.evaluate_file' do
    let(:model) { instance_double(CovLoupe::CoverageModel) }

    [
      { desc: 'a US-ASCII default external', external: Encoding::US_ASCII, internal: nil },
      { desc: 'a US-ASCII default internal', external: Encoding::UTF_8, internal: Encoding::US_ASCII },
    ].each do |tc|
      it "reads a predicate with non-ASCII source as UTF-8 with #{tc[:desc]} encoding" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'predicate.rb')
          File.write(path, "->(_model) { 'café'.length == 4 }\n")

          result = with_default_encodings(external: tc[:external], internal: tc[:internal]) do
            described_class.evaluate_file(path, model)
          end

          expect(result).to be(true)
        end
      end
    end
  end
end
