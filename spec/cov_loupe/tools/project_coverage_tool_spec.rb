# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/project_coverage_tool'

RSpec.describe CovLoupe::Tools::ProjectCoverageTool do
  subject(:call_tool) { described_class.call(root: root, server_context: server_context) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:server_context) { null_server_context }

  let(:presenter_stubs) do
    {
      relative_files:                 [],
      root_warning:                   nil,
      relative_skipped_files:         [],
      relative_not_in_coverage_files: [],
      relative_newer_files:           [],
      relative_deleted_files:         [],
      relative_length_mismatch_files: [],
      relative_unreadable_files:      [],
      timestamp_status:               'ok',
    }
  end

  before do
    setup_mcp_response_stub
  end

  # The text the tool returns for these arguments.
  def output_for(**args)
    response_text(described_class.call(root: root, server_context: server_context, **args))
  end

  # Calls the tool for table output from a ProjectCoveragePresenter double with these stubs.
  def table_output_with(overrides)
    model = instance_double(CovLoupe::CoverageModel, format_table: "Mock\nTable")
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

    presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter,
      presenter_stubs.merge(overrides))
    allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)

    output_for(format: 'table')
  end

  # Stubs the model and a ProjectCoveragePresenter double returning an empty list payload.
  def stub_list_presenter(payload_overrides = {})
    allow(CovLoupe::CoverageModel).to receive(:new).and_return(instance_double(CovLoupe::CoverageModel))
    presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter,
      payload: empty_list_payload(payload_overrides), root_warning: nil)
    allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
  end

  describe 'format parameter' do
    context 'with default format (json)' do
      it 'returns JSON by default' do
        output = output_for
        data = JSON.parse(output)
        expect(data).to have_key('files')
        expect(data).not_to have_key('counts')
      end

      it 'includes all expected keys in JSON output' do
        output = output_for
        data = JSON.parse(output)
        expected_keys = %w[files skipped_files not_in_coverage_files newer_files
          deleted_files length_mismatch_files unreadable_files timestamp_status]
        expected_keys.each do |key|
          expect(data).to have_key(key), "Expected key '#{key}' to be present"
        end
      end
    end

    context 'with format: pretty_json' do
      it 'returns formatted JSON with indentation' do
        output = output_for(format: 'pretty_json')
        expect(output).to include("\n")
        data = JSON.parse(output)
        expect(data).to have_key('files')
      end
    end

    context 'with format: yaml' do
      it 'returns YAML-formatted output' do
        output = output_for(format: 'yaml')
        expect(output).to start_with('---')
        expect(output).to include('files:')
        expect(output).to include('timestamp_status:')
      end
    end

    context 'with format: amazing_print' do
      it 'returns AmazingPrint-formatted output' do
        output = output_for(format: 'amazing_print')
        expect(output).to include('files')
        expect(output).to include('timestamp_status')
      end
    end

    context 'with format: table' do
      it 'returns a formatted table with Unicode box-drawing characters' do
        output = output_for(format: 'table')
        expect(output).to include('┌', '─', '│', '┘')
        expect(output).to include('File', 'Covered', 'Total')
      end

      it 'includes file coverage data in the table' do
        output = output_for(format: 'table')
        expect(output).to include('lib/foo.rb', 'lib/bar.rb')
      end
    end

    context 'with format: inspect' do
      it 'returns Ruby #inspect-formatted output' do
        output = output_for(format: 'inspect')
        # Hash#inspect's "key"=>value spacing is Ruby-version-dependent
        # (Ruby 3.4+ adds spaces around `=>`), so match either form.
        expect(output).to match(/"files"\s*=>/)
      end
    end

    context 'with format: puts' do
      it 'returns Kernel#puts-formatted output' do
        output = output_for(format: 'puts')
        expect(output).to match(/"files"\s*=>/)
        expect(output).to end_with("\n")
      end
    end

    context 'with format: pretty_print' do
      it 'returns multi-line PP-formatted output' do
        output = output_for(format: 'pretty_print')
        expect(output).to match(/"files"\s*=>/)
        expect(output.lines.count).to be > 1
      end
    end
  end

  describe 'format abbreviations' do
    {
      'j' => 'json', 'J' => 'pretty_json', 'y' => 'yaml', 'a' => 'amazing_print',
      'i' => 'inspect', 'p' => 'puts', 'P' => 'pretty_print', 't' => 'table'
    }.each do |code, long_name|
      it "accepts #{code} as #{long_name}" do
        expect(output_for(format: code)).to eq(output_for(format: long_name))
      end
    end
  end

  # These direct-call tests bypass MCP input-schema validation and exercise the
  # tool's equivalent internal validation. In real MCP traffic, the schema
  # rejects invalid `format`/`sort_order` enum values before the tool runs but
  # returns the same tool-result error shape with `isError: true`.
  describe 'invalid format (direct tool call)' do
    it 'returns an error response for invalid format' do
      response = described_class.call(root: root, format: 'invalid_format',
        server_context: server_context)
      expect_mcp_tool_error(response)
      expect(response.content.first['type']).to eq('text')
      text = response_text(response)
      expect(text).to include('Error')
    end

    %w[pretty-json awesome_print ap].each do |alias_name|
      it "rejects the noncanonical alias '#{alias_name}'" do
        response = described_class.call(root: root, format: alias_name,
          server_context: server_context)
        expect_mcp_tool_error(response)
        text = response_text(response)
        expect(text).to include('Error')
      end
    end
  end

  describe 'sort_order parameter validation (direct tool call)' do
    it 'accepts valid values: ascending, descending, a, d' do
      %w[ascending descending a d].each do |sort_order|
        response = described_class.call(
          root:           root,
          sort_order:     sort_order,
          server_context: server_context
        )
        expect(response).to be_a(MCP::Tool::Response)
        expect(response).not_to be_error
        expect(response.content.first['type']).to eq('text')
      end
    end

    it 'rejects invalid sort_order values' do
      response = described_class.call(
        root:           root,
        sort_order:     'invalid',
        server_context: server_context
      )
      expect_mcp_tool_error(response)
      text = response_text(response)
      expect(text).to include('Error')
      expect(text).to include('invalid')
    end
  end

  describe 'timestamp_status warnings' do
    it 'includes warnings array when timestamp_status is missing' do
      stub_list_presenter('timestamp_status' => 'missing')

      response = described_class.call(root: root, server_context: server_context)
      data = response_json(response)

      expect(data['timestamp_status']).to eq('missing')
      expect(data['warnings']).to be_an(Array)
      expect(data['warnings']).to include(
        'Coverage timestamps are missing. Time-based staleness checks were skipped.'
      )
    end

    it 'does not include warnings array when timestamp_status is ok' do
      response = described_class.call(root: root, server_context: server_context)
      data = response_json(response)

      expect(data['timestamp_status']).to eq('ok')
      expect(data['warnings']).to be_nil
    end
  end

  describe 'table format exclusions and warnings' do
    context 'with format: table' do
      it 'includes timestamp warning when timestamps are missing' do
        output = table_output_with(timestamp_status: 'missing')

        expect(output).to include('WARNING: Coverage timestamps are missing')
      end
    end

    it 'does not include exclusions summary when format is JSON' do
      stub_list_presenter

      output = output_for
      data = JSON.parse(output)

      expect(data['not_in_coverage_files']).to be_empty
    end
  end

  describe 'table format exclusion categories and skipped rows' do
    {
      relative_not_in_coverage_files: ['Files not in coverage data (2):', %w[lib/a.rb lib/b.rb]],
      relative_newer_files:           ['Files newer than coverage (1):', %w[lib/newer.rb]],
      relative_deleted_files:         ['Deleted files with coverage (1):', %w[lib/gone.rb]],
      relative_length_mismatch_files: ['Line count mismatches (1):', %w[lib/mismatch.rb]],
      relative_unreadable_files:      ['Unreadable files (1):', %w[lib/locked.rb]],
    }.each do |stub_name, (heading, files)|
      it "lists #{stub_name.to_s.delete_prefix('relative_').tr('_', ' ')} under '#{heading}'" do
        output = table_output_with(stub_name => files)

        expect(output).to include('Files excluded from coverage:', heading)
        files.each { |file| expect(output).to include("  - #{file}") }
        expect(output).to include('Run with --raise-on-stale true to exit when files are excluded.')
      end
    end

    it 'omits categories that have no entries' do
      output = table_output_with(relative_newer_files: %w[lib/newer.rb])

      expect(output).to include('Files newer than coverage (1):')
      expect(output).not_to include('Files not in coverage data', 'Deleted files', 'Unreadable files',
        'Line count mismatches')
    end

    context 'with skipped rows' do
      let(:skipped_rows) do
        [
          { 'file' => 'lib/bad.rb', 'error' => 'invalid coverage data' },
          { 'file' => 'lib/worse.rb', 'error' => 'lines is not an array' },
        ]
      end

      it 'reports each skipped row in the exclusions summary' do
        output = table_output_with(relative_skipped_files: skipped_rows)

        expect(output).to include(
          'Files skipped due to errors (2):',
          '  - lib/bad.rb: invalid coverage data',
          '  - lib/worse.rb: lines is not an array'
        )
      end

      it 'appends a pluralized skipped-rows warning' do
        output = table_output_with(relative_skipped_files: skipped_rows)

        expect(output).to include(
          'WARNING: 2 coverage rows skipped due to errors:',
          'Run again with --raise-on-stale true to exit when rows are skipped.'
        )
      end

      it 'uses the singular form for a single skipped row' do
        output = table_output_with(relative_skipped_files: skipped_rows.first(1))

        expect(output).to include('WARNING: 1 coverage row skipped due to errors:')
        expect(output).not_to include('1 coverage rows')
      end
    end

    it 'emits no skipped-rows warning when nothing was skipped' do
      output = table_output_with({})

      expect(output).to eq("Mock\nTable")
    end
  end

  describe 'output_chars parameter with table format' do
    it 'uses Unicode box-drawing by default' do
      output = output_for(format: 'table')

      expect(output).to include('┌', '─', '│', '┘')
    end

    it 'uses ASCII characters with output_chars: "ascii"' do
      output = output_for(format: 'table', output_chars: 'ascii')

      expect(output).to include('+', '-', '|')
      expect(output).not_to include('┌')
    end

    it 'uses ASCII characters with short form "a"' do
      output = output_for(format: 'table', output_chars: 'a')

      expect(output).to include('+', '-', '|')
      expect(output).not_to include('┌')
    end

    it 'uses Unicode with output_chars: "fancy"' do
      output = output_for(format: 'table', output_chars: 'fancy')

      expect(output).to include('┌', '─', '│')
    end
  end

  describe 'raise_on_stale parameter' do
    it 'passes raise_on_stale to model configuration' do
      stub_list_presenter

      described_class.call(root: root, raise_on_stale: true, server_context: server_context)

      expect(CovLoupe::CoverageModel).to have_received(:new).with(
        root:           root,
        coverage_file:  nil,
        raise_on_stale: true,
        file_globs:     []
      )
    end
  end
end
