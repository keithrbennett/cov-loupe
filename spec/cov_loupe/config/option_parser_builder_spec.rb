# frozen_string_literal: true

require 'spec_helper'
require 'shellwords'

RSpec.describe CovLoupe::OptionParserBuilder do
  describe 'help Examples section' do
    def self.help_examples
      help_text = described_class.new(CovLoupe::AppConfig.new).build_option_parser.help
      help_text.split("Examples:\n", 2).last.lines.map(&:strip).grep(/\Acov-loupe /)
    end

    it 'contains examples' do
      expect(self.class.help_examples).not_to be_empty
    end

    help_examples.each do |example|
      it "parses `#{example}`" do
        argv = example.shellsplit.drop(1)
        parser = CovLoupe::ConfigParser.new
        parser.parse_options(argv)
        cmd, *cmd_args = argv
        subcommand = CovLoupe.subcommand_for(cmd)

        expect(subcommand).not_to be_nil
        parser.parse_subcommand_options(subcommand, cmd_args)
        expect(cmd_args.none? { |arg| arg.start_with?('-') }).to be(true)
      end
    end
  end

  describe '#build_subcommand_option_parser' do
    def switches(parser)
      parser.top.list.grep(OptionParser::Switch).flat_map { |sw| sw.short + sw.long }
    end

    let(:builder) { described_class.new(CovLoupe::AppConfig.new) }

    it 'defines every global option except those allowed only before the subcommand' do
      all = switches(builder.build_option_parser).flat_map do |flag|
        flag.include?('[no-]') ? [flag.sub('[no-]', ''), flag.sub('[no-]', 'no-')] : [flag]
      end
      expected = all - described_class::BEFORE_SUBCOMMAND_ONLY

      expect(switches(builder.build_subcommand_option_parser)).to match_array(expected)
      expect(described_class::BEFORE_SUBCOMMAND_ONLY - all).to be_empty
    end

    it "leaves out OptionParser's built-in --help and --version" do
      parser = builder.build_subcommand_option_parser
      %w[--help --version].each do |flag|
        expect { parser.permute([flag]) }.to raise_error(OptionParser::InvalidOption)
      end
    end
  end
end
