# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::FileTool do
  {
    CovLoupe::Tools::FileCoverageSummaryTool  => :summary_for,
    CovLoupe::Tools::FileCoverageRawTool      => :raw_for,
    CovLoupe::Tools::FileCoverageDetailedTool => :detailed_for,
    CovLoupe::Tools::FileUncoveredLinesTool   => :uncovered_for,
  }.each do |tool, payload_method|
    describe tool.name.split('::').last do
      it 'has the file input schema, requiring path' do
        schema = tool.input_schema.to_h

        expect(schema[:properties].keys).to include(:path, :root, :coverage_file)
        expect(schema[:required]).to eq(['path'])
      end

      it "derives #{payload_method} from its class name, a CoverageModel method" do
        expect(tool.send(:payload_method)).to eq(payload_method)
        expect(CovLoupe::CoverageModel.method_defined?(payload_method)).to be(true)
      end
    end
  end

  describe '.underscore' do
    it 'converts CamelCase, including after digits, and does not split on a letter d' do
      {
        'FileCoverageSummary' => 'file_coverage_summary',
        'HTMLParser'          => 'html_parser',
        'Utf8Tool'            => 'utf8_tool',
        'Add'                 => 'add',
      }.each do |input, expected|
        expect(described_class.send(:underscore, input)).to eq(expected)
      end
    end
  end
end
