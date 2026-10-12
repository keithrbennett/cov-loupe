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
      it "places global options before the subcommand in `#{example}`" do
        cli = CovLoupe::CoverageCLI.new
        argv = example.shellsplit.drop(1)
        cli.send(:parse_options!, argv)
        cmd = cli.instance_variable_get(:@cmd)
        cmd_args = cli.instance_variable_get(:@cmd_args)

        expect(cmd).not_to be_nil
        expect { cli.send(:check_for_misplaced_global_options, cmd, cmd_args) }.not_to raise_error
      end
    end
  end
end
