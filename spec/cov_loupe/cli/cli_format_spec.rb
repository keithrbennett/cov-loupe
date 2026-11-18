# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::CoverageCLI, 'format option' do
  def run_cli(*argv)
    run_fixture_cli_output(*argv)
  end

  describe 'format normalization' do
    it 'normalizes short format aliases' do
      output = run_cli('--format', 'j', 'list')
      expect(output).to include('"files":', '"percentage":')
      data = JSON.parse(output)
      expect(data['files']).to be_an(Array)
    end

    it 'normalizes table format' do
      output = run_cli('--format', 't', 'list')
      expect(output).to include('File', '%') # Table output
      expect(output).not_to include('"files"') # Not JSON
    end

    it 'supports yaml format' do
      output = run_cli('--format', 'y', 'list')
      expect(output).to include('---', 'files:', 'file:')
    end

    it 'supports amazing_print format' do
      output = run_cli('--format', 'a', 'list')
      # AmazingPrint output contains colored/formatted structure
      expect(output).to match(/:files|"files"/)
    end

    it 'supports inspect format' do
      output = run_cli('--format', 'i', 'list')
      # Hash#inspect's "key"=>value spacing is Ruby-version-dependent
      # (Ruby 3.4+ adds spaces around `=>`), so match either form.
      expect(output).to match(/"files"\s*=>/)
    end

    it 'supports pretty_print format' do
      output = run_cli('--format', 'P', 'list')
      # Hash#inspect's "key"=>value spacing is Ruby-version-dependent
      # (Ruby 3.4+ adds spaces around `=>`), so match either form.
      expect(output).to match(/"files"\s*=>/)
      expect(output.lines.count).to be > 1
    end

    it 'supports puts format' do
      output = run_cli('--format', 'p', 'list')
      # Hash#inspect's "key"=>value spacing is Ruby-version-dependent
      # (Ruby 3.4+ adds spaces around `=>`), so match either form.
      expect(output).to match(/"files"\s*=>/)
    end
  end

  describe 'option order requirements' do
    it 'works with format option before subcommand' do
      output = run_cli('--format', 'json', 'list')
      data = JSON.parse(output)
      expect(data).to have_key('files')
    end

    it 'works with format option after subcommand' do
      data = JSON.parse(run_cli('list', '--format', 'json'))
      expect(data).to have_key('files')
    end

    it 'lets an option after the subcommand override one before it' do
      data = JSON.parse(run_cli('--format', 'table', 'list', '--format', 'json'))
      expect(data).to have_key('files')
    end
  end

  describe 'format with different subcommands' do
    it 'works with totals subcommand' do
      output = run_cli('--format', 'json', 'totals')
      data = JSON.parse(output)
      %w[percentage tracking file_counts].each { |key| expect(data).to have_key(key) }
    end

    it 'works with summary subcommand' do
      output = run_cli('--format', 'json', 'summary', 'lib/foo.rb')
      data = JSON.parse(output)
      expect(data).to have_key('file')
      expect(data).to include('percentage', 'stale')
    end
  end
end
