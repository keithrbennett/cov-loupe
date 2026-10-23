# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::CoverageCLI, 'with source that is not valid UTF-8' do
  let(:root) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(root, 'lib'))
    File.binwrite(File.join(root, 'lib/latin1.rb'), "x = 'caf\xE9'\n")
    FileUtils.mkdir_p(File.join(root, 'coverage'))
    File.write(File.join(root, 'coverage/coverage.json'), JSON.generate(coverage_json_document(
      coverage: { 'lib/latin1.rb' => { 'lines' => [1] } }, timestamp: Time.now.to_i + 60)))
  end

  after { FileUtils.rm_rf(root) }

  def run_detailed(format)
    run_cli_with_status('-R', root, '-f', format, '--source', 'full', 'detailed', 'lib/latin1.rb')
  end

  # The table shows the raw byte; the other text formats show it escaped, as Ruby's inspect does.
  { 'table' => "caf\xE9".b, 'inspect' => 'caf\\xE9', 'puts' => 'caf\\xE9',
    'pretty_print' => 'caf\\xE9', 'amazing_print' => 'caf\\xE9' }.each do |format, expected|
    it "shows the source in #{format} format" do
      out, err, status = run_detailed(format)
      aggregate_failures do
        expect(status).to eq(0), err
        expect(out.b).to include(expected.b)
      end
    end
  end

  %w[json pretty_json yaml].each do |format|
    it "fails with an error naming the file in #{format} format" do
      _out, err, status = run_detailed(format)
      aggregate_failures do
        expect(status).not_to eq(0)
        expect(err).to include('Source file is not valid UTF-8: lib/latin1.rb')
      end
    end
  end
end
