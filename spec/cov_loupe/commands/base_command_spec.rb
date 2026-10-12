# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::Commands::BaseCommand do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:cli_context) { CovLoupe::CoverageCLI.new }

  # Create a test command class that exposes protected methods for testing
  let(:test_command_class) do
    Class.new(CovLoupe::Commands::BaseCommand) do
      def execute(args)
        # Not needed for these tests
      end

      # Expose protected methods for testing
      def public_handle_with_path(args, name, &)
        handle_with_path(args, name, &)
      end

      def public_format_percentage(percentage)
        format_percentage(percentage)
      end
    end
  end

  let(:test_command) { test_command_class.new(cli_context) }

  describe '#format_percentage' do
    {
      nil      => 'n/a',
      0.0      => '0.00%',
      66.66667 => '66.67%',
      100.0    => '100.00%',
    }.each do |percentage, expected|
      it "formats #{percentage.inspect} as #{expected.inspect}" do
        expect(test_command.public_format_percentage(percentage)).to eq(expected)
      end
    end
  end

  describe '#handle_with_path' do
    context 'when Errno::ENOENT is raised' do
      it 'converts to FileNotFoundError with correct message' do
        args = ['lib/missing.rb']

        # Stub the block to raise Errno::ENOENT
        expect do
          test_command.public_handle_with_path(args, 'test') do |_path|
            raise Errno::ENOENT, 'No such file or directory'
          end
        end.to raise_error(CovLoupe::FileNotFoundError, 'File not found: lib/missing.rb')
      end

      it 'includes the path from the args in the error message' do
        args = ['some/other/path.rb']

        expect do
          test_command.public_handle_with_path(args, 'test') do |_path|
            raise Errno::ENOENT, 'No such file or directory'
          end
        end.to raise_error(CovLoupe::FileNotFoundError, %r{some/other/path\.rb})
      end
    end

    context 'when Errno::EACCES is raised' do
      it 'converts to FilePermissionError with correct message' do
        args = ['lib/secret.rb']

        # Stub the block to raise Errno::EACCES
        expect do
          test_command.public_handle_with_path(args, 'test') do |_path|
            raise Errno::EACCES, 'Permission denied'
          end
        end.to raise_error(CovLoupe::FilePermissionError, 'Permission denied: lib/secret.rb')
      end

      it 'includes the path from the args in the error message' do
        args = ['/root/protected.rb']

        expect do
          test_command.public_handle_with_path(args, 'test') do |_path|
            raise Errno::EACCES, 'Permission denied'
          end
        end.to raise_error(CovLoupe::FilePermissionError, %r{/root/protected\.rb})
      end
    end

    context 'when no path is provided' do
      it 'raises UsageError' do
        args = []

        expect do
          test_command.public_handle_with_path(args, 'summary') do |_path|
            # Should not reach here
          end
        end.to raise_error(CovLoupe::UsageError, /summary <path>/)
      end
    end

    context 'when successful' do
      it 'yields the path to the block' do
        args = %w[lib/foo.rb]
        yielded_path = nil

        test_command.public_handle_with_path(args, 'test') do |path|
          yielded_path = path
        end

        expect(yielded_path).to eq('lib/foo.rb')
      end

      it 'shifts the path from args' do
        args = %w[lib/foo.rb]

        test_command.public_handle_with_path(args, 'test') do |_path|
          # Block execution
        end

        expect(args).to be_empty
      end

      it 'rejects extra arguments after path' do
        args = %w[lib/foo.rb extra args]

        expect do
          test_command.public_handle_with_path(args, 'test') do |_path|
            # Should not reach here
          end
        end.to raise_error(CovLoupe::UsageError, /Unexpected argument.*extra args/)
      end
    end
  end
end
