# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCLI, 'table format for all commands' do
  describe 'table format consistency' do
    [
      { name: 'list',      argv: ['list'],                 headers: %w[File %] },
      { name: 'summary',   argv: %w[summary lib/foo.rb],   headers: %w[File %] },
      { name: 'detailed',  argv: %w[detailed lib/foo.rb],  headers: %w[Line Hits] },
      { name: 'uncovered', argv: %w[uncovered lib/bar.rb], headers: ['Line'] },
      { name: 'raw',       argv: %w[raw lib/foo.rb],       headers: %w[Line Hits] },
    ].each do |config|
      it "#{config[:name]} command produces formatted table" do
        output = run_fixture_cli_output('--format', 'table', *config[:argv])
        expect(output).to include('│') # Box drawing character
        config[:headers].each { |header| expect(output).to include(header) }
      end
    end
  end
end
