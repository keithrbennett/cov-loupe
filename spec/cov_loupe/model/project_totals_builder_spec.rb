# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/model/project_totals_builder'

RSpec.describe CovLoupe::ProjectTotalsBuilder do
  subject(:builder) { described_class.new(root: root) }

  let(:root) { File.expand_path('/proj') }
  let(:list_result) do
    {
      'files'                 => [
        { 'file' => File.join(root, 'lib/a.rb'), 'covered' => 3, 'total' => 4, 'stale' => 'ok' },
        { 'file' => File.join(root, 'lib/b.rb'), 'covered' => 1, 'total' => 2, 'stale' => 'newer' },
        { 'file' => File.join(root, 'lib/c.rb'), 'covered' => 0, 'total' => 5, 'stale' => 'unreadable' },
      ],
      'skipped_files'         => [{ 'file' => File.join(root, 'lib/d.rb') }],
      'missing_tracked_files' => ['lib/e.rb'],
      # c.rb has a row and d.rb is skipped, so only f.rb counts as unreadable without a row.
      'unreadable_files'      => ['lib/c.rb', 'lib/d.rb', 'lib/f.rb'],
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

  it 'builds the full payload when tracking is enabled' do
    expect(builder.build(list_result, tracked_globs: 'lib/**/*.rb')).to eq(
      'lines'            => {
        'covered' => 3, 'uncovered' => 1, 'total' => 4, 'percentage' => 75.0,
        'included_files' => 1, 'excluded_files' => 2
      },
      'tracking'         => { 'enabled' => true, 'globs' => ['lib/**/*.rb'] },
      'files'            => {
        'total'            => 6,
        'with_coverage'    => with_coverage,
        'without_coverage' => {
          'total'   => 3,
          'by_type' => { 'missing_from_coverage' => 1, 'unreadable' => 1, 'skipped' => 1 },
        },
      },
      'timestamp_status' => 'ok'
    )
  end

  it 'omits the without-coverage bucket when tracking is disabled' do
    result = builder.build(list_result, tracked_globs: [])

    aggregate_failures do
      expect(result['tracking']).to eq('enabled' => false, 'globs' => [])
      expect(result['files']).to eq('total' => 3, 'with_coverage' => with_coverage)
    end
  end
end
