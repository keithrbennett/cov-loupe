# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::StalenessMessageFormatter do
  let(:cov_timestamp) { Time.now.to_i - 3600 } # 1 hour ago

  describe 'output_chars: :ascii mode' do
    let(:unicode_path) { '/path/to/café/file.rb' }
    let(:unicode_resultset) { '/project/données/coverage/.resultset.json' }

    describe '#format_project_details' do
      it 'converts file paths to ASCII' do
        formatter = described_class.new(
          cov_timestamp:      cov_timestamp,
          coverage_file_path: unicode_resultset,
          output_chars:       :ascii
        )

        result = formatter.format_project_details(
          newer_files:           [unicode_path],
          missing_files:         [],
          deleted_files:         [],
          length_mismatch_files: [],
          unreadable_files:      []
        )

        aggregate_failures do
          expect(result).not_to include('é')
          expect(result).to include('cafe') # é transliterated
          expect(result).to include('donnees') # é transliterated
        end
      end

      it 'converts resultset path to ASCII' do
        formatter = described_class.new(
          cov_timestamp:      cov_timestamp,
          coverage_file_path: unicode_resultset,
          output_chars:       :ascii
        )

        result = formatter.format_project_details(
          newer_files:           [],
          missing_files:         [],
          deleted_files:         [],
          length_mismatch_files: [],
          unreadable_files:      []
        )

        expect(result).not_to include('é')
        expect(result).to include('donnees')
      end
    end

    describe '#format_single_file_details' do
      it 'converts resultset path to ASCII' do
        formatter = described_class.new(
          cov_timestamp:      cov_timestamp,
          coverage_file_path: unicode_resultset,
          output_chars:       :ascii
        )

        result = formatter.format_single_file_details(
          file_path:  '/some/file.rb',
          file_mtime: Time.now,
          src_len:    100,
          cov_len:    100
        )

        expect(result).not_to include('é')
        expect(result).to include('donnees')
      end
    end
  end

  describe 'output_chars: :fancy mode' do
    let(:unicode_path) { '/path/to/café/file.rb' }

    it 'preserves Unicode in file paths' do
      formatter = described_class.new(
        cov_timestamp:      cov_timestamp,
        coverage_file_path: nil,
        output_chars:       :fancy
      )

      result = formatter.format_project_details(
        newer_files:           [unicode_path],
        missing_files:         [],
        deleted_files:         [],
        length_mismatch_files: [],
        unreadable_files:      []
      )

      expect(result).to include('café')
    end
  end

  describe 'default mode (no output_chars specified)' do
    it 'preserves Unicode by default' do
      formatter = described_class.new(
        cov_timestamp:      cov_timestamp,
        coverage_file_path: '/path/café/.resultset.json'
      )

      result = formatter.format_project_details(
        newer_files:           ['/file/tëst.rb'],
        missing_files:         [],
        deleted_files:         [],
        length_mismatch_files: [],
        unreadable_files:      []
      )

      # Default mode preserves Unicode (assumes UTF-8 terminal)
      expect(result).to include('café')
      expect(result).to include('tëst')
    end
  end
end
