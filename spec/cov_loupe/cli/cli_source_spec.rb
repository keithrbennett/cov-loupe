# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCLI do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  it 'renders uncovered source without error for fixture file' do
    out, err, status = run_fixture_cli_with_status(
      '--source', 'uncovered', '--context-lines', '1', '--color=false', 'uncovered', 'lib/foo.rb'
    )
    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to match(%r{File:\s+lib/foo\.rb})
    expect(out).to include('│')  # Table format
    expect(out).to show_source_table_or_fallback
  end

  it 'renders full source for uncovered command without brittle spacing' do
    out, err, status = run_fixture_cli_with_status(
      '--source', 'full', '--color=false', 'uncovered', 'lib/foo.rb'
    )
    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to include('│')  # Table format
    expect(out).to include('66.66%')
    expect(out).to show_source_table_or_fallback
  end

  it 'renders source for summary with uncovered mode without crashing' do
    out, err, status = run_fixture_cli_with_status(
      '--source', 'uncovered', '--context-lines', '1', '--color=false', 'summary', 'lib/foo.rb'
    )
    expect(status).to eq(0)
    expect(err).to eq('')
    expect(out).to include('lib/foo.rb')
    expect(out).to include('66.66%')
    expect(out).to include('│')  # Table format
    expect(out).to show_source_table_or_fallback
  end
end
