# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/project_coverage_tool'

RSpec.describe CovLoupe::Tools::ProjectCoverageTool do
  subject(:call_tool) { described_class.call(root: root, server_context: server_context) }

  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:server_context) { null_server_context }

  before do
    setup_mcp_response_stub
  end

  describe 'format parameter' do
    context 'with default format (json)' do
      def run_with_default_format
        described_class.call(root: root, server_context: server_context).content.first['text']
      end

      it 'returns JSON by default' do
        output = run_with_default_format
        data = JSON.parse(output)
        expect(data).to have_key('files')
        expect(data).to have_key('counts')
      end

      it 'includes all expected keys in JSON output' do
        output = run_with_default_format
        data = JSON.parse(output)
        expected_keys = %w[files counts skipped_files missing_tracked_files newer_files
          deleted_files length_mismatch_files unreadable_files timestamp_status]
        expected_keys.each do |key|
          expect(data).to have_key(key), "Expected key '#{key}' to be present"
        end
      end
    end

    context 'with format: pretty_json' do
      def run_with_pretty_json
        described_class.call(root: root, format: 'pretty_json',
          server_context: server_context).content.first['text']
      end

      it 'returns formatted JSON with indentation' do
        output = run_with_pretty_json
        expect(output).to include("\n")
        data = JSON.parse(output)
        expect(data).to have_key('files')
      end
    end

    context 'with format: yaml' do
      def run_with_yaml
        described_class.call(root: root, format: 'yaml',
          server_context: server_context).content.first['text']
      end

      it 'returns YAML-formatted output' do
        output = run_with_yaml
        expect(output).to start_with('---')
        expect(output).to include('files:')
        expect(output).to include('counts:')
      end
    end

    context 'with format: amazing_print' do
      def run_with_amazing_print
        described_class.call(root: root, format: 'amazing_print',
          server_context: server_context).content.first['text']
      end

      it 'returns AmazingPrint-formatted output' do
        output = run_with_amazing_print
        expect(output).to include('files')
        expect(output).to include('counts')
      end
    end

    context 'with format: table' do
      def run_with_table
        described_class.call(root: root, format: 'table',
          server_context: server_context).content.first['text']
      end

      it 'returns a formatted table with Unicode box-drawing characters' do
        output = run_with_table
        expect(output).to include('┌', '─', '│', '┘')
        expect(output).to include('File', 'Covered', 'Total')
      end

      it 'includes file coverage data in the table' do
        output = run_with_table
        expect(output).to include('lib/foo.rb', 'lib/bar.rb')
      end
    end

    context 'with format: inspect' do
      def run_with_inspect
        described_class.call(root: root, format: 'inspect',
          server_context: server_context).content.first['text']
      end

      it 'returns Ruby #inspect-formatted output' do
        output = run_with_inspect
        # Hash#inspect's "key"=>value spacing is Ruby-version-dependent
        # (Ruby 3.4+ adds spaces around `=>`), so match either form.
        expect(output).to match(/"files"\s*=>/)
      end
    end

    context 'with format: puts' do
      def run_with_puts
        described_class.call(root: root, format: 'puts',
          server_context: server_context).content.first['text']
      end

      it 'returns Kernel#puts-formatted output' do
        output = run_with_puts
        expect(output).to match(/"files"\s*=>/)
        expect(output).to end_with("\n")
      end
    end

    context 'with format: pretty_print' do
      def run_with_pretty_print
        described_class.call(root: root, format: 'pretty_print',
          server_context: server_context).content.first['text']
      end

      it 'returns multi-line PP-formatted output' do
        output = run_with_pretty_print
        expect(output).to match(/"files"\s*=>/)
        expect(output.lines.count).to be > 1
      end
    end
  end

  describe 'format abbreviations' do
    it 'accepts j as json' do
      output = described_class.call(root: root, format: 'j',
        server_context: server_context).content.first['text']
      data = JSON.parse(output)
      expect(data).to have_key('files')
    end

    it 'accepts J as pretty_json' do
      output = described_class.call(root: root, format: 'J',
        server_context: server_context).content.first['text']
      expect(output).to include("\n")
      data = JSON.parse(output)
      expect(data).to have_key('files')
    end

    it 'accepts y as yaml' do
      output = described_class.call(root: root, format: 'y',
        server_context: server_context).content.first['text']
      expect(output).to start_with('---')
    end

    it 'accepts a as amazing_print' do
      output = described_class.call(root: root, format: 'a',
        server_context: server_context).content.first['text']
      expect(output).to include('files')
    end

    it 'accepts i as inspect' do
      output = described_class.call(root: root, format: 'i',
        server_context: server_context).content.first['text']
      expect(output).to match(/"files"\s*=>/)
    end

    it 'accepts p as puts' do
      output = described_class.call(root: root, format: 'p',
        server_context: server_context).content.first['text']
      expect(output).to match(/"files"\s*=>/)
    end

    it 'accepts P as pretty_print' do
      output = described_class.call(root: root, format: 'P',
        server_context: server_context).content.first['text']
      expect(output).to match(/"files"\s*=>/)
    end

    it 'accepts t as table' do
      output = described_class.call(root: root, format: 't',
        server_context: server_context).content.first['text']
      expect(output).to include('┌')
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
      text = response.content.first['text']
      expect(text).to include('Error')
    end

    %w[pretty-json awesome_print ap].each do |alias_name|
      it "rejects the noncanonical alias '#{alias_name}'" do
        response = described_class.call(root: root, format: alias_name,
          server_context: server_context)
        expect_mcp_tool_error(response)
        text = response.content.first['text']
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
      text = response.content.first['text']
      expect(text).to include('Error')
      expect(text).to include('invalid')
    end
  end

  describe 'timestamp_status warnings' do
    let(:setup_presenter_with_timestamp_status) do
      ->(status) do
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

        test_payload = {
          'files'                 => [],
          'counts'                => { 'total' => 0, 'ok' => 0, 'stale' => 0 },
          'skipped_files'         => [],
          'missing_tracked_files' => [],
          'newer_files'           => [],
          'deleted_files'         => [],
          'length_mismatch_files' => [],
          'unreadable_files'      => [],
          'timestamp_status'      => status,
        }

        presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
        allow(presenter).to receive(:relativized_payload).and_return(test_payload)
      end
    end

    it 'includes warnings array when timestamp_status is missing' do
      setup_presenter_with_timestamp_status.call('missing')

      response = described_class.call(root: root, server_context: server_context)
      data = JSON.parse(response.content.first['text'])

      expect(data['timestamp_status']).to eq('missing')
      expect(data['warnings']).to be_an(Array)
      expect(data['warnings']).to include(
        'Coverage timestamps are missing. Time-based staleness checks were skipped.'
      )
    end

    it 'does not include warnings array when timestamp_status is ok' do
      response = described_class.call(root: root, server_context: server_context)
      data = JSON.parse(response.content.first['text'])

      expect(data['timestamp_status']).to eq('ok')
      expect(data['warnings']).to be_nil
    end
  end

  describe 'table format exclusions and warnings' do
    context 'with format: table' do
      it 'includes exclusions summary when tracked files are missing' do
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
        allow(model).to receive(:relativize) { |p| p }

        relativizer = instance_double(CovLoupe::PathRelativizer)
        allow(model).to receive_messages(
          relativizer:  relativizer,
          skipped_rows: [],
          format_table: "Mock\nTable"
        )

        payload = {
          'files'                 => [{ 'file' => 'lib/foo.rb', 'percentage' => 100.0, 'covered' => 10,
                                      'total' => 10, 'stale' => 'ok' }],
          'skipped_files'         => [],
          'missing_tracked_files' => ['lib/missing.rb'],
          'newer_files'           => [],
          'deleted_files'         => [],
          'length_mismatch_files' => [],
          'unreadable_files'      => [],
        }
        allow(model).to receive(:list).and_return(payload)

        presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
        allow(presenter).to receive_messages(
          relative_files:                 payload['files'],
          relative_skipped_files:         [],
          relative_missing_tracked_files: ['lib/missing.rb'],
          relative_newer_files:           [],
          relative_deleted_files:         [],
          relative_length_mismatch_files: [],
          relative_unreadable_files:      [],
          timestamp_status:               'ok'
        )

        output = described_class.call(
          root:           root,
          format:         'table',
          tracked_globs:  ['lib/**/*.rb'],
          server_context: server_context
        ).content.first['text']

        expect(output).to include(
          'Files excluded from coverage:',
          'Missing tracked files',
          'lib/missing.rb'
        )
      end

      it 'includes timestamp warning when timestamps are missing' do
        model = instance_double(CovLoupe::CoverageModel)
        allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)
        allow(model).to receive(:relativize) { |p| p }

        relativizer = instance_double(CovLoupe::PathRelativizer)
        allow(model).to receive_messages(
          relativizer:  relativizer,
          skipped_rows: [],
          format_table: "Mock\nTable"
        )

        payload = {
          'files'                 => [],
          'skipped_files'         => [],
          'missing_tracked_files' => [],
          'newer_files'           => [],
          'deleted_files'         => [],
          'length_mismatch_files' => [],
          'unreadable_files'      => [],
        }
        allow(model).to receive(:list).and_return(payload)

        presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
        allow(presenter).to receive_messages(
          relative_files:                 [],
          relative_skipped_files:         [],
          relative_missing_tracked_files: [],
          relative_newer_files:           [],
          relative_deleted_files:         [],
          relative_length_mismatch_files: [],
          relative_unreadable_files:      [],
          timestamp_status:               'missing'
        )

        output = described_class.call(
          root:           root,
          format:         'table',
          server_context: server_context
        ).content.first['text']

        expect(output).to include('WARNING: Coverage timestamps are missing')
      end
    end

    it 'does not include exclusions summary when format is JSON' do
      model = instance_double(CovLoupe::CoverageModel)
      allow(CovLoupe::CoverageModel).to receive(:new).and_return(model)

      test_payload = {
        'files'                 => [],
        'counts'                => { 'total' => 0, 'ok' => 0, 'stale' => 0 },
        'skipped_files'         => [],
        'missing_tracked_files' => [],
        'newer_files'           => [],
        'deleted_files'         => [],
        'length_mismatch_files' => [],
        'unreadable_files'      => [],
        'timestamp_status'      => 'ok',
      }

      presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
      allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
      allow(presenter).to receive(:relativized_payload).and_return(test_payload)

      output = described_class.call(root: root, server_context: server_context).content.first['text']
      data = JSON.parse(output)

      expect(data['missing_tracked_files']).to be_empty
    end
  end

  describe 'output_chars parameter with table format' do
    it 'uses Unicode box-drawing by default' do
      output = described_class.call(
        root:           root,
        format:         'table',
        server_context: server_context
      ).content.first['text']

      expect(output).to include('┌', '─', '│', '┘')
    end

    it 'uses ASCII characters with output_chars: "ascii"' do
      output = described_class.call(
        root:           root,
        format:         'table',
        output_chars:   'ascii',
        server_context: server_context
      ).content.first['text']

      expect(output).to include('+', '-', '|')
      expect(output).not_to include('┌')
    end

    it 'uses ASCII characters with short form "a"' do
      output = described_class.call(
        root:           root,
        format:         'table',
        output_chars:   'a',
        server_context: server_context
      ).content.first['text']

      expect(output).to include('+', '-', '|')
      expect(output).not_to include('┌')
    end

    it 'uses Unicode with output_chars: "fancy"' do
      output = described_class.call(
        root:           root,
        format:         'table',
        output_chars:   'fancy',
        server_context: server_context
      ).content.first['text']

      expect(output).to include('┌', '─', '│')
    end
  end

  describe 'raise_on_stale parameter' do
    it 'passes raise_on_stale to model configuration' do
      model = instance_double(CovLoupe::CoverageModel)
      allow(CovLoupe::CoverageModel).to receive(:new).with(
        root:           root,
        coverage_file:  nil,
        raise_on_stale: true,
        tracked_globs:  []
      ).and_return(model)

      test_payload = {
        'files'                 => [],
        'counts'                => { 'total' => 0, 'ok' => 0, 'stale' => 0 },
        'skipped_files'         => [],
        'missing_tracked_files' => [],
        'newer_files'           => [],
        'deleted_files'         => [],
        'length_mismatch_files' => [],
        'unreadable_files'      => [],
        'timestamp_status'      => 'ok',
      }

      presenter = instance_double(CovLoupe::Presenters::ProjectCoveragePresenter)
      allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new).and_return(presenter)
      allow(presenter).to receive(:relativized_payload).and_return(test_payload)

      described_class.call(root: root, raise_on_stale: true, server_context: server_context)

      expect(CovLoupe::CoverageModel).to have_received(:new).with(
        root:           root,
        coverage_file:  nil,
        raise_on_stale: true,
        tracked_globs:  []
      )
    end
  end
end
