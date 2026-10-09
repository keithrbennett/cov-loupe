# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CLI enumerated option parsing' do
  def parse!(argv)
    cli = CovLoupe::CoverageCLI.new
    cli.send(:parse_options!, argv.dup)
    cli
  end

  shared_examples 'parses option' do |cases|
    cases.each do |c|
      it "parses #{c[:argv].join(' ')}" do
        cli = parse!(c[:argv])
        expect(cli.config.public_send(c[:accessor])).to eq(c[:expected])
      end
    end
  end

  describe 'accepts short and long forms' do
    it_behaves_like 'parses option', [
      { argv: %w[--sort-order a list], accessor: :sort_order, expected: :ascending },
      { argv: %w[--sort-order d list], accessor: :sort_order, expected: :descending },
      { argv: %w[--sort-order ascending list], accessor: :sort_order, expected: :ascending },
      { argv: %w[--sort-order descending list], accessor: :sort_order, expected: :descending },

      { argv: %w[--source f summary lib/foo.rb], accessor: :source_mode, expected: :full },
      { argv: %w[--source u summary lib/foo.rb], accessor: :source_mode, expected: :uncovered },
      { argv: %w[--source full summary lib/foo.rb], accessor: :source_mode, expected: :full },
      { argv: %w[--source uncovered summary lib/foo.rb], accessor: :source_mode,
        expected: :uncovered },
      { argv: %w[--source n summary lib/foo.rb], accessor: :source_mode, expected: nil },
      { argv: %w[--source none summary lib/foo.rb], accessor: :source_mode, expected: nil },
      { argv: %w[-s n summary lib/foo.rb], accessor: :source_mode, expected: nil },
      { argv: %w[-s none summary lib/foo.rb], accessor: :source_mode, expected: nil },
      { argv: %w[-sf -sn summary lib/foo.rb], accessor: :source_mode, expected: nil },
      { argv: %w[-sn -sf summary lib/foo.rb], accessor: :source_mode, expected: :full },

      { argv: %w[-S yes list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale yes list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=false list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=yes list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale no list], accessor: :raise_on_stale, expected: false },

      { argv: %w[--error-mode off list], accessor: :error_mode, expected: :off },
      { argv: %w[--error-mode o list], accessor: :error_mode, expected: :off },
      { argv: %w[--error-mode log list], accessor: :error_mode, expected: :log },
      { argv: %w[--error-mode debug list], accessor: :error_mode, expected: :debug },

      # -e short flag for --error-mode
      { argv: %w[-e off list], accessor: :error_mode, expected: :off },
      { argv: %w[-e d list], accessor: :error_mode, expected: :debug },

      # --output-chars with long and short forms
      { argv: %w[--output-chars default list], accessor: :output_chars, expected: :default },
      { argv: %w[--output-chars d list], accessor: :output_chars, expected: :default },
      { argv: %w[--output-chars fancy list], accessor: :output_chars, expected: :fancy },
      { argv: %w[--output-chars f list], accessor: :output_chars, expected: :fancy },
      { argv: %w[--output-chars ascii list], accessor: :output_chars, expected: :ascii },
      { argv: %w[--output-chars a list], accessor: :output_chars, expected: :ascii },
      { argv: %w[-O ascii list], accessor: :output_chars, expected: :ascii },
      { argv: %w[-O f list], accessor: :output_chars, expected: :fancy },
    ]
  end

  describe 'boolean options with BooleanType accept various values' do
    it_behaves_like 'parses option', [
      # --raise-on-stale with = syntax
      { argv: %w[--raise-on-stale=yes list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=no list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=true list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=false list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=on list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=off list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=y list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=n list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=+ list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=- list], accessor: :raise_on_stale, expected: false },
      { argv: %w[--raise-on-stale=1 list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale=0 list], accessor: :raise_on_stale, expected: false },

      # --raise-on-stale with space syntax
      { argv: %w[--raise-on-stale yes list], accessor: :raise_on_stale, expected: true },
      { argv: %w[--raise-on-stale no list], accessor: :raise_on_stale, expected: false },

      # --color with various values
      { argv: %w[--color=yes list], accessor: :color, expected: true },
      { argv: %w[--color=no list], accessor: :color, expected: false },
      { argv: %w[--color=true list], accessor: :color, expected: true },
      { argv: %w[--color=false list], accessor: :color, expected: false },
      { argv: %w[--color on list], accessor: :color, expected: true },
      { argv: %w[--color off list], accessor: :color, expected: false },

      # -C short flag for --color
      { argv: %w[-C no list], accessor: :color, expected: false },
      { argv: %w[-C false list], accessor: :color, expected: false },
    ]
  end

  shared_examples 'rejects invalid option' do |cases|
    cases.each do |c|
      it "exits 2 for #{c[:argv].join(' ')}" do
        _out, err, status = run_cli_with_status(*c[:argv])
        expect(status).to eq(2)
        expect(err).to include('Error:') if c.fetch(:check_error_prefix, true)
        expect(err).to include('invalid argument')
      end
    end
  end

  describe 'rejects invalid values' do
    it_behaves_like 'rejects invalid option', [
      { argv: %w[--sort-order asc list] },
      { argv: %w[--source x summary lib/foo.rb] },
      { argv: %w[--error-mode bad list] },
      { argv: %w[--error-mode on list] },
      { argv: %w[--error-mode trace list] },
      { argv: %w[--output-chars invalid list] },
      { argv: %w[--output-chars unicode list] },
      { argv: %w[-O utf8 list] },
    ]
  end

  describe 'missing value hints' do
    # OptionParser consumes the next argument as the value, which then fails validation
    it_behaves_like 'rejects invalid option', [
      { argv: %w[--source summary lib/foo.rb], check_error_prefix: false },
      { argv: %w[--raise-on-stale list], check_error_prefix: false },
      { argv: %w[-S list], check_error_prefix: false },
      { argv: %w[--color list], check_error_prefix: false },
      { argv: %w[-C list], check_error_prefix: false },
    ]
  end
end
