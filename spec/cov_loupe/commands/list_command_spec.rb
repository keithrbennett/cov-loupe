# frozen_string_literal: true

require 'spec_helper'
require_relative '../shared_examples/formatted_command_examples'

RSpec.describe CovLoupe::Commands::ListCommand do
  include_context 'with a project1 command'

  describe '#execute' do
    context 'with table format' do
      it 'outputs a formatted table' do
        output = capture_command_output(command, [])

        expect(output).to include('│', 'lib/foo.rb', 'lib/bar.rb')
      end
    end

    it 'rejects extra arguments' do
      expect do
        command.execute(%w[extra args])
      end.to raise_error(CovLoupe::UsageError, /Unexpected argument.*extra args/)
    end

    it_behaves_like 'a command with formatted output', [], %w[files timestamp_status]

    it 'prints JSON summary using the presenter payload when json mode is enabled' do
      cli_context.config.format = :json
      cli_context.config.sort_order = :ascending

      _result, output, _err = capture_io do
        command.execute([])
      end

      payload = JSON.parse(output)

      expect(payload['files']).to be_an(Array)
      percentages = payload['files'].map { |row| row['percentage'] }
      expect(percentages).to eq(percentages.sort)
      expect(payload).not_to have_key('counts')
    end

    context 'when coverage rows are skipped due to errors' do
      let(:foo_path) { File.expand_path('lib/foo.rb', root) }

      before do
        cli_context.config.format = :table

        # Stub CoverageModel to trigger resolver fallback for foo.rb
        allow(CovLoupe::CoverageModel).to receive(:new).and_wrap_original do |method, **kwargs|
          model = method.call(**kwargs)
          foo_entry = model.send(:coverage_map)[foo_path]

          allow(CovLoupe::ListRowBuilder).to receive(:lines_from_entry).and_wrap_original do |m, entry, **kw|
            # Return nil for foo.rb only, to trigger the resolver fallback
            entry.equal?(foo_entry) ? nil : m.call(entry, **kw)
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
          command.execute([])
        end

        expect(warnings).to include('Files skipped due to errors (1):')
        expect(warnings.scan('lib/foo.rb').length).to eq(1)
        expect(warnings).to include('lib/foo.rb')
        expect(warnings).to include('corrupt data')
      end

      it 'raises immediately when raise-on-stale is enabled' do
        cli_context.config.raise_on_stale = true

        expect do
          suppress_io do
            command.execute([])
          end
        end.to raise_error(CovLoupe::CoverageDataError, /corrupt data/)
      end

      it 'filters skipped rows warning by file_globs' do
        # Use file_globs that excludes the skipped file (lib/foo.rb)
        cli_context.config.file_globs = ['lib/bar.rb']

        _result, _out, warnings = capture_io do
          command.execute([])
        end

        # The skipped file (lib/foo.rb) is outside file_globs, so no warning should appear
        expect(warnings).not_to include('WARNING', 'coverage row', 'lib/foo.rb')
      end
    end

    context 'when exclusions include deleted files' do
      let(:presenter) do
        instance_double(
          CovLoupe::Presenters::ProjectCoveragePresenter,
          relative_files:                 [],
          relative_not_in_coverage_files: [],
          relative_newer_files:           [],
          relative_deleted_files:         ['lib/old.rb'],
          relative_length_mismatch_files: [],
          relative_unreadable_files:      [],
          root_warning:                   nil,
          relative_skipped_files:         [],
          timestamp_status:               'ok',
          payload:                        { 'files' => [] }
        )
      end

      before do
        cli_context.config.format = :table
        # Allow the model to be created naturally, only mock the presenter
        allow(CovLoupe::Presenters::ProjectCoveragePresenter).to receive(:new) do |model:, **_opts|
          # Stub the model method that ListCommand calls
          allow(model).to receive(:format_table).and_return("table\n")
          presenter
        end
      end

      it 'prints the deleted files section in the exclusions summary on stderr' do
        _result, _out, output = capture_io do
          command.execute([])
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
