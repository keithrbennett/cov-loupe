# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::StalenessMessageFormatter do
  let(:cov_timestamp) { Time.now.to_i - 3600 } # 1 hour ago

  describe 'file paths' do
    it 'shows the coverage file path unchanged in single-file details' do
      coverage_file = "/proj/x\u2192y/caf\u00e9/coverage.json"
      formatter = described_class.new(cov_timestamp: cov_timestamp, coverage_file_path: coverage_file)

      result = formatter.format_single_file_details(file_path: 'lib/a.rb', file_mtime: Time.now,
        src_len: 1, cov_len: 1)

      expect(result).to include(coverage_file)
    end

    it 'shows paths exactly as given, never altering their characters' do
      formatter = described_class.new(
        cov_timestamp:      cov_timestamp,
        coverage_file_path: '/path/café/coverage.json'
      )

      result = formatter.format_project_details(
        newer_files:           ["/file/t\u00ebst\u2192.rb"],
        missing_files:         [],
        deleted_files:         [],
        length_mismatch_files: [],
        unreadable_files:      []
      )

      expect(result).to include('café', "t\u00ebst\u2192.rb")
    end
  end
end
