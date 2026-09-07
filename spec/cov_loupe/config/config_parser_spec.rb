# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::ConfigParser do
  describe '.parse' do
    # v7 reassigned -c from --context-lines to --coverage-file and moved
    # --context-lines to -n. Pin what each short form sets, not merely that the
    # parser recognizes it.
    [
      { args: %w[-c build/coverage], attr: :coverage_file, expected: 'build/coverage' },
      { args: %w[--coverage-file build/coverage], attr: :coverage_file, expected: 'build/coverage' },
      { args: %w[-n 3], attr: :source_context, expected: 3 },
      { args: %w[--context-lines 3], attr: :source_context, expected: 3 },
    ].each do |tc|
      it "'#{tc[:args].join(' ')}' sets #{tc[:attr]} to #{tc[:expected].inspect}" do
        config = described_class.parse(tc[:args] + %w[summary lib/foo.rb])

        expect(config.public_send(tc[:attr])).to eq(tc[:expected])
      end
    end

    it 'leaves the subcommand and its arguments in argv' do
      argv = %w[-c build/coverage -n 3 summary lib/foo.rb]
      described_class.parse(argv)

      expect(argv).to eq(%w[summary lib/foo.rb])
    end
  end
end
