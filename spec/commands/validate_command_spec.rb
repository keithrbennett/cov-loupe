# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe CovLoupe::Commands::ValidateCommand do
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

    it 'exits 1 when predicate returns falsy value' do
      with_temp_predicate("->(model) { false }\n") do |path|
        _out, _err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(1)
      end
    end

    it 'exits 2 when predicate raises an error' do
      with_temp_predicate("->(model) { raise 'Boom!' }\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(2)
        expect(err).to include('Predicate error: Boom!')
      end
    end

    it 'shows backtrace when predicate errors with --error-mode debug' do
      with_temp_predicate("->(model) { raise 'Boom!' }\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          '--error-mode', 'debug',
          'validate', path
        )
        expect(status).to eq(2)
        expect(err).to include('Predicate error: Boom!')
        # With trace mode, should show backtrace
        expect(err).to match(/predicate.*\.rb:\d+/)
      end
    end

    it 'exits 2 when predicate file is not found' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '/nonexistent/predicate.rb'
      )
      expect(status).to eq(2)
      expect(err).to include('Predicate file not found')
    end

    it 'exits 2 when predicate has syntax error' do
      with_temp_predicate("-> { this is invalid syntax\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(2)
        expect(err).to include('Syntax error in predicate file')
      end
    end

    it 'exits 2 when predicate is not callable' do
      with_temp_predicate("42\n") do |path|
        _out, err, status = run_fixture_cli_with_status(
          'validate', path
        )
        expect(status).to eq(2)
        expect(err).to include('Predicate must be callable')
      end
    end

    it 'provides model to predicate that can query coverage' do
      # Test that the predicate receives a working CoverageModel
      with_temp_predicate(<<~RUBY) do |path|
        ->(model) do
          # Access coverage data via the model
          summary = model.summary_for('lib/foo.rb')
          summary['summary']['percent_covered'] > 50  # Should be true for foo.rb
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

    it 'exits 1 when predicate code returns falsy value' do
      _out, _err, status = run_fixture_cli_with_status(
        'validate', '-i', '->(model) { false }'
      )
      expect(status).to eq(1)
    end

    it 'exits 2 when predicate code raises an error' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', "->(model) { raise 'Boom!' }"
      )
      expect(status).to eq(2)
      expect(err).to include('Predicate error: Boom!')
    end

    it 'exits 2 when predicate code has syntax error' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', '-> { invalid syntax'
      )
      expect(status).to eq(2)
      expect(err).to include('Syntax error in predicate code')
    end

    it 'exits 2 when predicate code is not callable' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i', '42'
      )
      expect(status).to eq(2)
      expect(err).to include('Predicate must be callable')
    end

    it 'provides model to predicate that can query coverage' do
      code = <<~RUBY.strip
        ->(model) { model.summary_for('lib/foo.rb')['summary']['percent_covered'] > 50 }
      RUBY
      _out, _err, status = run_fixture_cli_with_status(
        'validate', '-i', code
      )
      expect(status).to eq(0)
    end
  end

  describe 'error handling' do
    it 'raises error when no file or -i flag provided' do
      _out, err, status = run_fixture_cli_with_status(
        'validate'
      )
      expect(status).to eq(1)
      expect(err).to include('validate <file> | -i <code>')
    end

    it 'raises error when -i flag provided without code' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '-i'
      )
      expect(status).to eq(1)
      expect(err).to include('validate -i <code>')
    end

    it 'raises error when unknown option is provided' do
      _out, err, status = run_fixture_cli_with_status(
        'validate', '--unknown-option'
      )
      expect(status).to eq(1)
      expect(err).to include('Unknown option for validate: --unknown-option')
    end
  end
end
