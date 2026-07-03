# frozen_string_literal: true

require 'spec_helper'

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

    it 'shows helpful error when global option comes after subcommand' do
      _out, err, status = run_fixture_cli_with_status('list', '--format', 'json')
      expect(status).to eq(1)
      expect(err).to include(
        'Global option(s) must come BEFORE the subcommand',
        'You used: list --format',
        'Correct: --format list',
        'Example:'
      )
    end
  end

  describe 'format with different subcommands' do
    it 'works with totals subcommand' do
      output = run_cli('--format', 'json', 'totals')
      data = JSON.parse(output)
      %w[lines tracking files].each { |key| expect(data).to have_key(key) }
    end

    it 'works with summary subcommand' do
      output = run_cli('--format', 'json', 'summary', 'lib/foo.rb')
      data = JSON.parse(output)
      expect(data).to have_key('file')
      expect(data).to have_key('summary')
    end
  end

  describe 'comprehensive misplaced option detection' do
    # Array of test cases: [description, args_array, expected_option_in_error]
    [
      # Short-form options
      ['short -f after list', %w[list -f json], '-f'],
      ['short -r after totals', %w[totals -r .resultset.json], '-r'],
      ['short -R after list', ['list', '-R', Dir.tmpdir], '-R'],
      ['short -o after list', %w[list -o a], '-o'],
      ['short -s after list', %w[list -s full], '-s'],
      ['short -S after list', %w[list -S error], '-S'],
      ['short -v after list', %w[list -v], '-v'],
      ['short -p after list', %w[list -p repo], '-p'],
      ['short -v after totals', %w[totals -v], '-v'],
      ['short -v after summary', %w[summary lib/foo.rb -v], '-v'],

      # Long-form options
      ['--sort-order after list', %w[list --sort-order ascending], '--sort-order'],
      ['--source after list', %w[list --source full], '--source'],
      ['--raise-on-stale after totals', %w[totals --raise-on-stale], '--raise-on-stale'],
      ['--color after list', %w[list --color], '--color'],
      ['--log-file after list', ['list', '--log-file', File.join(Dir.tmpdir, 'test.log')], '--log-file'],
      ['--version after list', %w[list --version], '--version'],
      ['--version after totals', %w[totals --version], '--version'],
      ['--version after summary', %w[summary lib/foo.rb --version], '--version'],
      ['--path-for after list', %w[list --path-for repo], '--path-for'],

      # Different subcommands
      ['option after summary', %w[summary lib/foo.rb --format json], '--format'],
      ['option after raw', %w[raw lib/foo.rb -f json], '-f'],
      ['option after detailed', %w[detailed lib/foo.rb -f json], '-f'],
      ['option after uncovered', ['uncovered', 'lib/foo.rb', '--root', Dir.tmpdir], '--root'],
    ].each do |desc, args, option|
      it "detects #{desc}" do
        _out, err, status = run_cli_with_status(*args)
        expect(status).to eq(1)
        expect(err).to include('Global option(s) must come BEFORE the subcommand')
        expect(err).to include(option)
      end
    end
  end
end
