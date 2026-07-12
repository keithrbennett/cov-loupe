# frozen_string_literal: true

require 'spec_helper'

OPTION_TESTS = {
  source:     {
    long:  '--source',
    short: '-s',
    text:  'Valid values for --source: f[ull]|u[ncovered]|n[one]',
  },
  error_mode: {
    long:  '--error-mode',
    short: nil,
    text:  'Valid values for --error-mode: o[ff]|l[og]|d[ebug]',
  },
  sort_order: {
    long:  '--sort-order',
    short: '-o',
    text:  'Valid values for --sort-order: a[scending]|d[escending]',
  },
}.freeze

RSpec.describe CovLoupe::OptionParsers::ErrorHelper do
  subject(:helper) { described_class.new(subcommands) }

  let(:subcommands) { %w[list summary raw uncovered detailed totals validate version] }

  # Helper method to test error output matches expected pattern
  def expect_error_output(error:, argv:, text:)
    stderr_output = capture_stderr do
      helper.handle_option_parser_error(error, argv: argv)
    end
    expect(stderr_output).to include(text)
  end

  describe '#handle_option_parser_error' do
    context 'with invalid enumerated option values' do
      OPTION_TESTS.each_value do |config|
        context "when parsing #{config[:long]} option" do
          let(:error) { OptionParser::InvalidArgument.new('invalid argument: xyz') }

          it 'suggests valid values for space-separated form with invalid value' do
            expect_error_output(
              error: error,
              argv:  [config[:long], 'xyz'],
              text:  config[:text]
            )
          end

          it 'suggests valid values for equal form with invalid value' do
            expect_error_output(
              error: error,
              argv:  ["#{config[:long]}=xyz"],
              text:  config[:text]
            )
          end

          if config[:short]
            it 'suggests valid values for short form with invalid value' do
              expect_error_output(
                error: error,
                argv:  [config[:short], 'xyz'],
                text:  config[:text]
              )
            end
          end
        end
      end

      context 'when handling --source option edge cases' do
        it 'suggests valid values when value is missing' do
          error = OptionParser::InvalidArgument.new('missing argument: --source')
          expect_error_output(
            error: error,
            argv:  %w[--source],
            text:  'Valid values for --source: f[ull]|u[ncovered]|n[one]'
          )
        end

        it 'suggests valid values when next token looks like an option' do
          error = OptionParser::InvalidArgument.new('invalid argument: --other')
          expect_error_output(
            error: error,
            argv:  %w[--source --other-option],
            text:  'Valid values for --source: f[ull]|u[ncovered]|n[one]'
          )
        end
      end

      context 'when handling raise-on-stale (boolean) option edge cases' do
        let(:boolean_error) { OptionParser::InvalidOption.new('invalid option: --raise-on-stale=maybe') }

        it 'does not suggest enum values for invalid boolean value' do
          stderr_output = capture_stderr do
            helper.handle_option_parser_error(boolean_error, argv: %w[--raise-on-stale=maybe])
          end

          expect(stderr_output).to include('invalid option')
          expect(stderr_output).not_to include('Valid values')
        end
      end
    end

    context 'with multiple options in argv' do
      it 'correctly identifies the problematic option among valid options' do
        error = OptionParser::InvalidArgument.new('invalid argument: bad')
        expect_error_output(
          error: error,
          argv:  %w[--resultset coverage --source bad --format json],
          text:  'Valid values for --source: f[ull]|u[ncovered]|n[one]'
        )
      end

      it 'handles equal form mixed with other options' do
        error = OptionParser::InvalidArgument.new('invalid argument: invalid')
        expect_error_output(
          error: error,
          argv:  %w[--format json --sort-order=invalid --resultset coverage],
          text:  'Valid values for --sort-order: a[scending]|d[escending]'
        )
      end
    end

    context 'when option is not an enumerated type' do
      it 'shows generic error message without enum hint' do
        error = OptionParser::InvalidArgument.new('invalid option: --unknown')

        stderr_output = capture_stderr do
          helper.handle_option_parser_error(error, argv: %w[--unknown])
        end

        expect(stderr_output).to match(/Error:.*invalid option.*--unknown/)
        expect(stderr_output).to include("Run 'cov-loupe --help'")
        expect(stderr_output).not_to include('Valid values')
      end
    end

    context 'when invalid option matches a subcommand' do
      it 'suggests using it as a subcommand instead' do
        error = OptionParser::InvalidOption.new('invalid option: --summary')

        stderr_output = capture_stderr do
          helper.handle_option_parser_error(error, argv: %w[--summary])
        end

        expect(stderr_output).to match(/Error:.*--summary/)
        expect(stderr_output).to include("Run 'cov-loupe --help'")
      end
    end

    context 'when exiting after invalid option' do
      it 'exits with status 1' do
        error = OptionParser::InvalidArgument.new('invalid argument: xyz')

        stderr_output = capture_stderr do
          expect do
            helper.handle_option_parser_error(error, argv: %w[--source xyz])
          end.to raise_error(SystemExit) do |e|
            expect(e.status).to eq(1)
          end
        end

        expect(stderr_output).to include('invalid argument: xyz')
      end
    end

    context 'when customizing usage hint' do
      it 'uses custom usage hint when provided' do
        error = OptionParser::InvalidArgument.new('invalid argument: xyz')

        expect do
          helper.handle_option_parser_error(error, argv: %w[--source xyz],
            usage_hint: 'Custom hint message')
        rescue SystemExit
          # Ignore exit call
        end.to output(/Custom hint message/).to_stderr
      end
    end
  end

  describe 'when handling edge cases' do
    it 'handles empty argv gracefully' do
      error = OptionParser::InvalidArgument.new('some error')
      expect_error_output(
        error: error,
        argv:  [],
        text:  'Error: invalid argument: some error'
      )
    end

    it 'handles argv with only valid options (no problematic enum)' do
      error = OptionParser::InvalidArgument.new('some error')

      stderr_output = capture_stderr do
        helper.handle_option_parser_error(error,
          argv: %w[--format json --resultset coverage])
      end

      expect(stderr_output).to include('Error: invalid argument: some error')
      expect(stderr_output).to include("Run 'cov-loupe --help'")
    end

    it 'does not show enum hint when all enum values are valid' do
      error = OptionParser::MissingArgument.new('missing argument: --resultset')

      stderr_output = capture_stderr do
        helper.handle_option_parser_error(error, argv: %w[--source full --resultset])
      end

      expect(stderr_output).to match(/Error:.*missing argument.*--resultset/)
      expect(stderr_output).not_to include('Valid values')
    end
  end
end
