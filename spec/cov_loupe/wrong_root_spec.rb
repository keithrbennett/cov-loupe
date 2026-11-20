# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Coverage keys are project-relative, so under the wrong root every file looks deleted.
RSpec.describe 'running against the wrong project root' do
  let(:wrong_root) { Dir.mktmpdir }
  let(:coverage_file) { FIXTURE_PROJECT1_COVERAGE_PATH }
  let(:warning) { 'The project root may be wrong: most files with coverage rows (2 of 2)' }
  let(:server_context) { null_server_context }
  let(:mcp_args) do
    { root: wrong_root, coverage_file: coverage_file, server_context: server_context }
  end

  after { FileUtils.remove_entry(wrong_root) }

  def cli_args(*args)
    ['--root', wrong_root, '--coverage-file', coverage_file, *args]
  end

  def mcp_text(tool, **args)
    tool.call(**mcp_args, **args).content.first['text']
  end

  [[], %w[--format json]].product(%w[list totals]).each do |format_args, command|
    it "warns on stderr and exits 0 for #{[*format_args, command].join(' ')}" do
      _stdout, stderr, status = run_cli_with_status(*cli_args(*format_args, command))

      expect(stderr).to include(warning, wrong_root)
      expect(status).to eq(0)
    end
  end

  it 'names the root when --raise-on-stale fails' do
    _stdout, stderr, status = run_cli_with_status(*cli_args('--raise-on-stale', 'true', 'list'))

    expect(stderr).to include(warning, wrong_root)
    expect(status).to eq(1)
  end

  [CovLoupe::Tools::ProjectCoverageTool, CovLoupe::Tools::ProjectCoverageTotalsTool].each do |tool|
    it "adds the warning to the #{tool.tool_name} warnings array" do
      warnings = JSON.parse(mcp_text(tool)).fetch('warnings')

      expect(warnings).to contain_exactly(a_string_including(warning, wrong_root))
    end
  end

  it 'appends the warning to the project_coverage table' do
    expect(mcp_text(CovLoupe::Tools::ProjectCoverageTool, format: 'table')).to include(warning)
  end

  context 'when coverage.json records an existing root' do
    let(:project_root) { File.dirname(FIXTURE_PROJECT1_COVERAGE_PATH, 2) }
    let(:coverage_file) do
      document = JSON.parse(File.read(FIXTURE_PROJECT1_COVERAGE_PATH))
      document['meta']['root'] = project_root
      File.join(wrong_root, 'coverage.json').tap { |path| File.write(path, JSON.generate(document)) }
    end
    let(:suggestion) { "The coverage file was generated with root #{project_root}." }

    %w[list totals].each do |command|
      it "suggests the recorded root for #{command}" do
        expect(run_cli_with_status(*cli_args(command))[1]).to include(warning, suggestion)
      end
    end

    it 'suggests the recorded root when --raise-on-stale fails' do
      _stdout, stderr, status = run_cli_with_status(*cli_args('--raise-on-stale', 'true', 'list'))

      expect(stderr).to include(warning, suggestion)
      expect(status).to eq(1)
    end

    it 'suggests the recorded root in the MCP warnings array' do
      warnings = JSON.parse(mcp_text(CovLoupe::Tools::ProjectCoverageTool)).fetch('warnings')

      expect(warnings).to contain_exactly(a_string_including(suggestion))
    end
  end

  it 'keeps the staleness summary in the error message' do
    model = CovLoupe::CoverageModel.new(root: wrong_root, coverage_file: coverage_file)

    expect { model.list(raise_on_stale: true) }.to raise_error(
      CovLoupe::CoverageDataProjectStaleError,
      /\ACoverage data appears stale for project\. #{Regexp.escape(warning)}/
    )
  end

  [CovLoupe::Tools::ProjectCoverageTool, CovLoupe::Tools::ProjectCoverageTotalsTool].each do |tool|
    it "lists the timestamp and root warnings together in #{tool.tool_name}" do
      no_timestamp_coverage = (FIXTURES_DIR / 'project_no_timestamp' / 'coverage' / 'coverage.json').to_s
      text = mcp_text(tool, coverage_file: no_timestamp_coverage)

      expect(JSON.parse(text).fetch('warnings')).to match(
        [*CovLoupe::Formatters::CoverageWarnings::TIMESTAMP_WARNING_LINES,
          a_string_including('most files with coverage rows (1 of 1)')]
      )
    end
  end

  context 'with the correct root' do
    let(:project_root) { File.dirname(coverage_file, 2) }

    [CovLoupe::Tools::ProjectCoverageTool, CovLoupe::Tools::ProjectCoverageTotalsTool].each do |tool|
      it "omits warnings from the #{tool.tool_name} payload" do
        expect(JSON.parse(mcp_text(tool, root: project_root))).not_to have_key('warnings')
      end
    end

    # Malformed rows are skipped, so neither command counts them, even when their sources
    # are missing.
    it 'does not count skipped rows in list or totals' do
      coverage = JSON.parse(File.read(coverage_file))
      # Three skipped rows of five would cross the threshold if they were counted.
      %w[gone1 gone2 gone3].each { |name| coverage['coverage']["lib/#{name}.rb"] = { 'lines' => 'bad' } }
      path = File.join(wrong_root, 'coverage.json')
      File.write(path, JSON.generate(coverage))

      %w[list totals].each do |command|
        _stdout, stderr, = run_cli_with_status('--root', project_root, '--coverage-file', path, command)

        expect(stderr).not_to include('project root may be wrong'), command
      end
    end

    # lib/bar.rb and lib/foo.rb exist under the root; lib/gone1.rb through lib/gone3.rb do not.
    context 'with file globs' do
      let(:coverage_path) do
        coverage = JSON.parse(File.read(coverage_file))
        %w[gone1 gone2 gone3].each { |name| coverage['coverage']["lib/#{name}.rb"] = { 'lines' => [1] } }
        File.join(wrong_root, 'coverage.json').tap { |path| File.write(path, JSON.generate(coverage)) }
      end

      def stderr_for(command, *glob_args)
        run_cli_with_status('--root', project_root, '--coverage-file', coverage_path,
          *glob_args, command)[1]
      end

      [
        [[], '(3 of 5)'],
        [%w[-g lib/gone*.rb], '(3 of 3)'],
        [%w[-g lib/foo.rb], nil],
      ].product(%w[list totals]).each do |(glob_args, count), command|
        it "#{count ? "warns with #{count}" : 'does not warn'} for #{[*glob_args, command].join(' ')}" do
          stderr = stderr_for(command, *glob_args)
          if count
            expect(stderr).to include("most files with coverage rows #{count}")
          else
            expect(stderr).not_to include('project root may be wrong')
          end
        end
      end
    end
  end
end
