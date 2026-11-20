# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCLI do
  def run_cli(*argv)
    run_fixture_cli_output(*argv)
  end

  it 'prints default table when no subcommand is given' do
    output = run_cli

    # Contains a header row and at least one data row with expected columns
    expect(output).to include('File', 'Covered', 'Total', 'lib/foo.rb', 'lib/bar.rb')
  end

  describe 'list command exclusions display' do
    it 'shows missing tracked files on stderr after the table' do
      stdout, stderr = run_fixture_cli_with_status('--tracked-globs', 'lib/**/*.rb', 'list').first(2)

      aggregate_failures do
        # Table should still be present with files that have coverage
        expect(stdout).to include('File', 'lib/foo.rb', 'lib/bar.rb')

        # Should show exclusions summary for files matching glob but without coverage
        expect(stderr).to include(
          'Files excluded from coverage:',
          'Files not in coverage data',
          'lib/uncovered_file.rb'
        )
      end
    end

    it 'does not show exclusions when there are none' do
      # Using a very specific glob that only matches files with coverage
      stdout, stderr = run_fixture_cli_with_status('--tracked-globs', 'lib/foo.rb', 'list').first(2)

      aggregate_failures do
        expect(stdout).to include('File')
        expect(stderr).not_to include('Files excluded from coverage:', 'Files not in coverage data')
      end
    end
  end
end
