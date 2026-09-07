# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::CoverageCLI do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli) { described_class.new }

  before do
    cli.config.root = root
    cli.config.coverage_file = FIXTURE_PROJECT1_COVERAGE_PATH
    cli.config.raise_on_stale = false
    cli.config.tracked_globs = nil
  end

  describe '#show_default_report' do
    it 'prints JSON summary using relativized payload when json mode is enabled' do
      cli.config.format = :json

      _result, output, _err = capture_io do
        cli.show_default_report(sort_order: :ascending, output: $stdout)
      end

      payload = JSON.parse(output)

      expect(payload['files']).to be_an(Array)
      expect(payload['files'].first['file']).to eq('lib/bar.rb').or eq('lib/foo.rb')
      expect(payload['counts']).to include('total', 'ok', 'stale')
    end

    context 'when coverage rows are skipped due to errors' do
      let(:foo_path) { File.expand_path('lib/foo.rb', root) }

      before do
        cli.config.format = :table

        # Stub CoverageModel to trigger resolver fallback for foo.rb
        allow(CovLoupe::CoverageModel).to receive(:new).and_wrap_original do |method, **kwargs|
          model = method.call(**kwargs)
          foo_entry = model.send(:coverage_map)[foo_path]

          allow(model).to receive(:extract_lines_from_entry).and_wrap_original do |m, entry|
            # Only trigger resolver fallback for foo.rb by returning nil
            if entry.equal?(foo_entry)
              nil # Trigger resolver fallback for foo.rb
            else
              m.call(entry)
            end
          end

          model
        end

        allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines).and_call_original
        allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:lookup_lines)
          .with(anything, foo_path, any_args)
          .and_raise(CovLoupe::CoverageDataError, 'corrupt data')
      end

      it 'prints a warning to stderr listing the skipped file' do
        _result, _out, warnings = capture_io do
          cli.show_default_report(sort_order: :ascending, output: $stdout)
        end

        expect(warnings).to include('WARNING: 1 coverage row skipped due to errors')
        expect(warnings).to include('lib/foo.rb')
        expect(warnings).to include('corrupt data')
      end

      it 'raises immediately when raise-on-stale is enabled' do
        cli.config.raise_on_stale = true

        expect do
          suppress_io do
            cli.show_default_report(sort_order: :ascending, output: $stdout)
          end
        end.to raise_error(CovLoupe::CoverageDataError, /corrupt data/)
      end

      it 'filters skipped rows warning by tracked_globs' do
        # Use tracked_globs that excludes the skipped file (lib/foo.rb)
        cli.config.tracked_globs = ['lib/bar.rb']

        _result, _out, warnings = capture_io do
          cli.show_default_report(sort_order: :ascending, output: $stdout)
        end

        # The skipped file (lib/foo.rb) is outside tracked_globs, so no warning should appear
        expect(warnings).not_to include('WARNING', 'coverage row', 'lib/foo.rb')
      end
    end

    context 'when exclusions include deleted files' do
      let(:presenter) do
        instance_double(
          CovLoupe::Presenters::ProjectCoveragePresenter,
          relative_files:                 [],
          relative_missing_tracked_files: [],
          relative_newer_files:           [],
          relative_deleted_files:         ['lib/old.rb'],
          relative_length_mismatch_files: [],
          relative_unreadable_files:      [],
          relative_skipped_files:         [],
          timestamp_status:               'ok'
        )
      end

      before do
        cli.config.format = :table
        # Allow the model to be created naturally, only mock the presenter
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new) do |model:, **_opts|
          # Stub model methods that are called in show_default_report
          allow(model).to receive_messages(format_table: "table\n", skipped_rows: [])
          presenter
        end
      end

      it 'prints the deleted files section in the exclusions summary on stderr' do
        _result, _out, output = capture_io do
          cli.show_default_report(sort_order: :ascending, output: $stdout)
        end

        expect(output).to include(
          'Files excluded from coverage:',
          'Deleted files with coverage (1):',
          '  - lib/old.rb'
        )
      end
    end
  end
end
