# frozen_string_literal: true

require 'fileutils'
require 'spec_helper'
require 'tmpdir'

RSpec.describe 'CLI --output-chars option' do
  describe '--output-chars ascii' do
    it 'produces ASCII table borders for list output' do
      output = run_fixture_cli_output('--output-chars', 'ascii', 'list')

      aggregate_failures do
        # ASCII border characters should be present
        expect(output).to include('+')
        expect(output).to include('-')
        expect(output).to include('|')

        # Unicode box-drawing characters should NOT be present
        expect(output).not_to include("\u250C") # top-left corner
        expect(output).not_to include("\u2500") # horizontal
        expect(output).not_to include("\u2502") # vertical
        expect(output).not_to include("\u2510") # top-right corner
      end
    end

    it 'produces ASCII table borders for default (no subcommand) output' do
      output = run_fixture_cli_output('--output-chars', 'ascii')

      aggregate_failures do
        expect(output).to include('+')
        expect(output).to include('|')
        expect(output).not_to include("\u250C")
        expect(output).not_to include("\u2502")
      end
    end
  end

  describe '--output-chars fancy' do
    it 'produces Unicode table borders' do
      output = run_fixture_cli_output('--output-chars', 'fancy', 'list')

      aggregate_failures do
        # Unicode box-drawing characters should be present
        expect(output).to include("\u250C") # top-left corner
        expect(output).to include("\u2500") # horizontal
        expect(output).to include("\u2502") # vertical
      end
    end
  end

  describe '-O short flag' do
    it 'works as alias for --output-chars' do
      output = run_fixture_cli_output('-O', 'ascii', 'list')

      expect(output).to include('+')
      expect(output).not_to include("\u250C")
    end
  end

  # ASCII mode changes only table borders and markers; data must reach the output unchanged.
  describe 'data with --output-chars ascii' do
    let(:file_name) { "caf\u00e9\u2192.rb" }
    let(:root) { Dir.mktmpdir }

    around { |example| with_utf8_default_external { example.run } }

    before do
      path = File.join(root, 'lib', file_name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "x = 1\ny = 2\n")
      FileUtils.mkdir_p(File.join(root, 'coverage'))
      document = coverage_json_document(coverage: { path => { 'lines' => [1, 0] } },
        timestamp: File.mtime(path).to_i + 60)
      File.write(File.join(root, 'coverage', 'coverage.json'), JSON.generate(document))
    end

    after { FileUtils.rm_rf(root) }

    %w[summary raw detailed uncovered].each do |subcommand|
      it "shows the file path unchanged in #{subcommand} output" do
        out, err, status = run_cli_with_status('-O', 'ascii', '--root', root, subcommand, "lib/#{file_name}")

        expect(status).to eq(0), err
        expect(out).to include("lib/#{file_name}")
      end
    end

    it 'shows tracked globs unchanged in totals output' do
      glob = "lib/caf\u00e9\u2192*.rb"
      out, err, status = run_cli_with_status('-O', 'ascii', '--root', root, '--tracked-globs', glob, 'totals')

      expect(status).to eq(0), err
      expect(out).to include(glob)
    end

    it 'shows an invalid option unchanged in the option parser error' do
      _out, err, status = run_cli_with_status('-O', 'ascii', '--root', root, "--caf\u00e9\u2192")

      expect(status).to eq(2)
      expect(err).to include("--caf\u00e9\u2192")
    end
  end
end
