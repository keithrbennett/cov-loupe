# frozen_string_literal: true

# Payloads with nothing to report, for stubbing presenters; pass string-keyed overrides.
module PayloadFixtures
  # A CoverageModel#list payload with no files.
  def empty_list_payload(overrides = {})
    {
      'files'                 => [],
      'skipped_files'         => [],
      'not_in_coverage_files' => [],
      'newer_files'           => [],
      'deleted_files'         => [],
      'length_mismatch_files' => [],
      'unreadable_files'      => [],
      'timestamp_status'      => 'ok',
    }.merge(overrides)
  end

  # A CoverageModel#project_totals payload with no files and no file globs.
  def empty_totals_payload(overrides = {})
    {
      'total' => 0, 'covered' => 0, 'uncovered' => 0, 'percentage' => 0,
      'file_globs' => [],
      'file_counts' => {
        'total'            => 0,
        'with_coverage'    => {
          'total' => 0,
          'ok'    => 0,
          'stale' => {
            'total'   => 0,
            'by_type' => {
              'deleted'         => 0,
              'newer'           => 0,
              'length_mismatch' => 0,
              'unreadable'      => 0,
            },
          },
        },
        'without_coverage' => {
          'total'   => 0,
          'by_type' => { 'not_in_coverage' => nil, 'skipped' => 0 },
        },
      },
      'timestamp_status' => 'ok'
    }.merge(overrides)
  end
end
