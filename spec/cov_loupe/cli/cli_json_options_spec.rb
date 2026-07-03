# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCLI, 'json format options' do
  def run_cli_output(*argv)
    run_fixture_cli_output(*argv)
  end

  describe 'JSON format options' do
    [
      { flag: 'j',           expect_compact: true },
      { flag: 'json',        expect_compact: true },
      { flag: 'J',           expect_compact: false },
      { flag: 'pretty_json', expect_compact: false },
    ].each do |test_case|
      it "produces #{test_case[:expect_compact] ? 'compact' : 'pretty'} JSON with -f #{test_case[:flag]}" do
        output = run_cli_output('-f', test_case[:flag], 'list')

        if test_case[:expect_compact]
          expect(output.strip.lines.count).to eq(1)
        else
          expect(output.strip.lines.count).to be > 1
        end
        data = JSON.parse(output)
        expect(data['files']).to be_an(Array)
      end
    end

    %w[p pretty-json].each do |flag|
      it "does not treat -f #{flag} as JSON" do
        _out, err, status = run_fixture_cli_with_status('-f', flag, 'list')
        if flag == 'p'
          # 'p' is now the canonical short code for :puts, not JSON.
          expect(status).to eq(0)
        else
          # 'pretty-json' is no longer a recognized alias.
          expect(status).to eq(1)
          expect(err).to include('invalid argument')
        end
      end
    end
  end
end
