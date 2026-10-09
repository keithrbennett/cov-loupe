# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tempfile'
require 'tmpdir'

RSpec.describe CovLoupe::Commands::ValidateCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }

  def with_temp_predicate(content)
    Tempfile.create(%w[predicate .rb]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end

  describe 'validate subcommand with file' do
    it 'exits 0 when predicate returns truthy value' do
      with_temp_predicate("->(model) { true }\n") do |path|
        _out, _err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(0)
      end
    end

    it 'exits 3 when predicate returns falsy value' do
      with_temp_predicate("->(model) { false }\n") do |path|
        _out, _err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(3)
      end
    end

    it 'exits 4 when predicate raises an error' do
      with_temp_predicate("->(model) { raise 'Boom!' }\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(4)
        expect(err).to include('Predicate error: Boom!')
      end
    end

    it 'shows backtrace when predicate errors with --error-mode debug' do
      with_temp_predicate("->(model) { raise 'Boom!' }\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          '--error-mode', 'debug',
          'validate', path
        )
        expect(status).to eq(4)
        expect(err).to include('Predicate error: Boom!')
        # With trace mode, should show backtrace
        expect(err).to match(/predicate.*\.rb:\d+/)
      end
    end

    it 'exits 4 when predicate file is not found' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '/nonexistent/predicate.rb'
      )
      expect(status).to eq(4)
      expect(err).to include('Predicate file not found')
    end

    it 'exits 4 when predicate has syntax error' do
      with_temp_predicate("-> { this is invalid syntax\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(4)
        expect(err).to include('Syntax error in predicate file')
      end
    end

    it 'exits 4 when predicate is not callable' do
      with_temp_predicate("42\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(4)
        expect(err).to include('Predicate must be callable')
      end
    end

    it 'provides model to predicate that can query coverage' do
      # Test that the predicate receives a working CoverageModel
      with_temp_predicate(<<~RUBY) do |path|
        ->(model) do
          # Access coverage data via the model
          summary = model.summary_for('lib/foo.rb')
          summary['summary']['percentage'] > 50  # Should be true for foo.rb
        end
      RUBY
        _out, _err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(0)
      end
    end
  end

  describe 'validate subcommand with -i/--inline flag' do
    it 'exits 0 when predicate code returns truthy value' do
      _out, _err, status = run_fixture_cli_with_status(
        'validate', '-i', '->(model) { true }'
      )
      expect(status).to eq(0)
    end

    it 'exits 3 when predicate code returns falsy value' do
      _out, _err, status = run_fixture_cli_with_status(
        'validate', '-i', '->(model) { false }'
      )
      expect(status).to eq(3)
    end

    it 'exits 4 when predicate code raises an error' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', "->(model) { raise 'Boom!' }"
      )
      expect(status).to eq(4)
      expect(err).to include('Predicate error: Boom!')
    end

    it 'exits 4 when predicate code has syntax error' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', '-> { invalid syntax'
      )
      expect(status).to eq(4)
      expect(err).to include('Syntax error in predicate code')
    end

    it 'exits 4 when predicate code is not callable' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', '42'
      )
      expect(status).to eq(4)
      expect(err).to include('Predicate must be callable')
    end

    it 'provides model to predicate that can query coverage' do
      code = <<~RUBY.strip
        ->(model) { model.summary_for('lib/foo.rb')['summary']['percentage'] > 50 }
      RUBY
      _out, _err, status = run_fixture_cli_with_status(
        'validate', '-i', code
      )
      expect(status).to eq(0)
    end
  end

  describe 'output characters' do
    it 'converts the debug backtrace to ASCII in ascii mode' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'prédicate_é.rb')
        File.write(path, "->(model) { raise 'Boom!' }\n")
        _out, err, status = run_fixture_cli_with_status(
          '--output-chars', 'ascii', '--error-mode', 'debug', '--log-file', ':off',
          'validate', path
        )
        expect(status).to eq(4)
        expect(err).to match(/pr.dicate_.\.rb:\d+/) # backtrace is shown
        expect(err).to be_ascii_only
      end
    end
  end

  describe 'logging' do
    it 'logs the predicate-side backtrace in debug mode, matching the terminal output' do
      Dir.mktmpdir do |dir|
        log_file = File.join(dir, 'cov_loupe.log')
        predicate = File.join(dir, 'my_failing_predicate.rb')
        File.write(predicate, "->(model) { raise 'Boom!' }\n")
        _out, err, status = run_fixture_cli_with_status(
          '--error-mode', 'debug', '--log-file', log_file, 'validate', predicate
        )
        expect(status).to eq(4)
        expect(err).to include('my_failing_predicate.rb:1')
        expect(File.read(log_file)).to include('my_failing_predicate.rb:1')
      end
    end

    it 'logs predicate errors to the configured log file like other CLI errors' do
      Dir.mktmpdir do |dir|
        log_file = File.join(dir, 'cov_loupe.log')
        _out, _err, status = run_fixture_cli_with_status(
          '--log-file', log_file, 'validate', '-i', "->(model) { raise 'Boom!' }"
        )
        expect(status).to eq(4)
        expect(File.read(log_file)).to include('ERROR', 'PredicateError', 'Boom!')
      end
    end
  end

  describe 'CovLoupe errors raised by the predicate itself' do
    %w[UsageError ConfigurationError].each do |error_class|
      it "exits 4, not 2, when the predicate raises #{error_class}" do
        _out, err, status = run_fixture_cli_with_status(
          'validate', '-i', "->(model) { raise CovLoupe::#{error_class}, 'from predicate' }"
        )
        expect(status).to eq(4)
        expect(err).to include('Predicate error: from predicate')
      end
    end
  end

  describe 'runtime errors are not predicate errors' do
    it 'exits 1 without a "Predicate error" label when the coverage file is missing' do
      _out, err, status = run_cli_with_status(
        '--coverage-file', 'does/not/exist.json', 'validate', '-i', '->(model) { true }'
      )
      expect(status).to eq(1)
      expect(err).to include('not found')
      expect(err).not_to include('Predicate error')
    end

    it 'exits 1 when the project coverage is stale and --raise-on-stale is set' do
      # Work on a copy so the checked-in fixture tree is never modified.
      Dir.mktmpdir do |tmp|
        FileUtils.cp_r(root, tmp, preserve: true)
        project = File.join(tmp, File.basename(root))
        File.write(File.join(project, 'lib', 'brand_new_file.rb'), "# new file\n")

        _out, err, status = run_cli_with_status(
          '--root', project, '--raise-on-stale', 'true', '--tracked-globs', 'lib/**/*.rb',
          'validate', '-i', '->(model) { model.list; true }'
        )
        expect(status).to eq(1)
        expect(err).to include('Coverage data stale')
        expect(err).not_to include('Predicate error')
      end
    end

    it 'exits 1 when the predicate itself triggers a coverage error' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', "->(model) { model.summary_for('lib/does_not_exist.rb') }"
      )
      expect(status).to eq(1)
      expect(err).not_to include('Predicate error')
    end
  end

  describe 'error handling' do
    it 'raises error when no file or -i flag provided' do
      _out, err, status = run_fixture_cli_with_status(
        'validate'
      )
      expect(status).to eq(2)
      expect(err).to include('validate <file> | -i <code>')
    end

    it 'raises error when -i flag provided without code' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i'
      )
      expect(status).to eq(2)
      expect(err).to include('validate -i <code>')
    end

    it 'raises error when unknown option is provided' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '--unknown-option'
      )
      expect(status).to eq(2)
      expect(err).to include('Unknown option for validate: --unknown-option')
    end
  end
end
