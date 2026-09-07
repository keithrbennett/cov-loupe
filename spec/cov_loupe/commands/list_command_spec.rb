# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::ListCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }
  let(:command) { described_class.new(cli_context) }

  before do
    cli_context.config.root = root
    cli_context.config.coverage_file = FIXTURE_PROJECT1_COVERAGE_PATH
    cli_context.config.format = :table
  end

  describe '#execute' do
    context 'with table format' do
      it 'outputs a formatted table' do
        output = capture_command_output(command, [])

        expect(output).to include('│', 'lib/foo.rb', 'lib/bar.rb')
      end
    end

    it 'rejects extra arguments' do
      expect do
        command.execute(%w[extra args])
      end.to raise_error(CovLoupe::UsageError, /Unexpected argument.*extra args/)
    end

    it_behaves_like 'a command with formatted output', [], %w[files counts]
  end
end
