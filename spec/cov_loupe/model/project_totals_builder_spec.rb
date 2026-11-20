# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/model/project_totals_builder'

RSpec.describe CovLoupe::ProjectTotalsBuilder do
  subject(:builder) { described_class.new }

  let(:root) { File.expand_path('/proj') }
  let(:list_result) do
    {
      'files'                 => [
        { 'file' => File.join(root, 'lib/a.rb'), 'covered' => 3, 'total' => 4, 'stale' => 'ok' },
        { 'file' => File.join(root, 'lib/b.rb'), 'covered' => 1, 'total' => 2, 'stale' => 'newer' },
        { 'file' => File.join(root, 'lib/c.rb'), 'covered' => 0, 'total' => 5, 'stale' => 'unreadable' },
      ],
      'skipped_files'         => [{ 'file' => File.join(root, 'lib/d.rb') }],
      'not_in_coverage_files' => ['lib/e.rb'],
      'timestamp_status'      => 'ok',
    }
  end
  let(:with_coverage) do
    {
      'total' => 3,
      'ok'    => 1,
      'stale' => {
        'total'   => 2,
        'by_type' => { 'deleted' => 0, 'newer' => 1, 'length_mismatch' => 0, 'unreadable' => 1 },
      },
    }
  end

  it 'builds the full payload when file globs are set' do
    expect(builder.build(list_result, file_globs: 'lib/**/*.rb')).to eq(
      'covered' => 3, 'uncovered' => 1, 'total' => 4, 'percentage' => 75.0,
      'file_globs' => ['lib/**/*.rb'],
      'file_counts' => {
        'total'            => 5,
        'with_coverage'    => with_coverage,
        'without_coverage' => {
          'total'   => 2,
          'by_type' => { 'not_in_coverage' => 1, 'skipped' => 1 },
        },
      },
      'timestamp_status' => 'ok'
    )
  end

  it 'counts skipped files, with not_in_coverage null, when no file globs are set' do
    # list_result still lists a file not in coverage: without globs it must be ignored, not counted.
    result = builder.build(list_result, file_globs: [])

    aggregate_failures do
      expect(result['file_globs']).to eq([])
      expect(result['file_counts']).to eq(
        'total'            => 4,
        'with_coverage'    => with_coverage,
        'without_coverage' => {
          'total'   => 1,
          'by_type' => { 'not_in_coverage' => nil, 'skipped' => 1 },
        }
      )
    end
  end
end
