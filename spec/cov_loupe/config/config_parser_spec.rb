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
      { args: %w[--allow-code-predicates], attr: :allow_code_predicates, expected: true },
      # A later --no- form overrides an earlier one, e.g. one set in COV_LOUPE_OPTS.
      { args: %w[--allow-code-predicates --no-allow-code-predicates], attr: :allow_code_predicates,
        expected: false },
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

  describe '#stopped_at_terminator?' do
    # order! removes a '--' it stops at, so the leftover arguments alone cannot show it.
    {
      %w[-f json] => false, %w[-f json list] => false, %w[--] => true,
      %w[-f json -- -h] => true, %w[-g --] => false
    }.each do |args, stopped|
      it "is #{stopped} after parsing #{args.inspect}" do
        parser = described_class.new
        parser.parse_options(args.dup)
        expect(parser.stopped_at_terminator?).to be(stopped)
      end
    end
  end

  describe '#parse_subcommand_options' do
    it 'parses options mixed with positional arguments, keeping their order' do
      parser = described_class.new
      args = %w[a -f json b --sort-order ascending c]
      parser.parse_subcommand_options('summary', args)

      expect(args).to eq(%w[a b c])
      expect(parser.config.format).to eq(:json)
      expect(parser.config.sort_order).to eq(:ascending)
    end

    it 'leaves the arguments after -- as positional arguments' do
      args = %w[-f json -- -odd.rb]
      described_class.new.parse_subcommand_options('summary', args)
      expect(args).to eq(%w[-odd.rb])
    end

    it "returns validate's inline code, taking the next argument even if it starts with '-'" do
      args = ['-i', '->(m) { true }']
      expect(described_class.new.parse_subcommand_options('validate', args)).to eq('->(m) { true }')
      expect(args).to be_empty
    end
  end
end
