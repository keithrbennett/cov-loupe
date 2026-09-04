# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe do
  def expect_listed_files(message, files)
    files.each { |file| expect(message).to include("  - #{file}") }
  end

  def expect_absent_files(message, files)
    files.each { |file| expect(message).not_to include("  - #{file}") }
  end

  describe CovLoupe::Error do
    describe '#user_friendly_message' do
      it 'returns the message for base Error class' do
        error = described_class.new('Base error message')
        expect(error.user_friendly_message).to eq('Base error message')
      end
    end
  end

  describe CovLoupe::ConfigurationError do
    describe '#user_friendly_message' do
      it 'prefixes message with "Configuration error:"' do
        error = described_class.new('Invalid option value')

        expect(error.user_friendly_message).to eq('Configuration error: Invalid option value')
      end

      it 'handles empty message' do
        error = described_class.new('')

        expect(error.user_friendly_message).to eq('Configuration error: ')
      end

      it 'handles nil message' do
        # When nil is passed to StandardError, it uses the class name as the message
        error = described_class.new(nil)

        expect(error.user_friendly_message).to eq('Configuration error: CovLoupe::ConfigurationError')
      end
    end
  end


  describe CovLoupe::CoverageFileNotFoundError do
    describe '#user_friendly_message' do
      it 'includes helpful tips in CLI mode' do
        # Create a CLI context (not MCP mode)
        error_handler = CovLoupe::ErrorHandlerFactory.for_cli
        context = CovLoupe.create_context(error_handler: error_handler, mode: :cli)
        CovLoupe.with_context(context) do
          error = described_class.new('Coverage data not found')
          message = error.user_friendly_message

          expect(message).to include(
            'File error: Coverage data not found',
            'Try one of the following:',
            'cd to a directory containing coverage/coverage.json',
            'Specify a coverage file: cov-loupe -r PATH',
            'Use -h for help: cov-loupe -h'
          )
        end
      end

      it 'does not include helpful tips in MCP mode' do
        # Create an MCP context
        error_handler = CovLoupe::ErrorHandlerFactory.for_mcp_server
        context = CovLoupe.create_context(error_handler: error_handler, mode: :mcp)
        CovLoupe.with_context(context) do
          error = described_class.new('Coverage data not found')
          message = error.user_friendly_message

          expect(message).to eq('File error: Coverage data not found')
          expect(message).not_to include('Try one of the following:')
        end
      end
    end
  end

  describe CovLoupe::CoverageDataStaleError do
    describe 'time formatting edge cases' do
      it 'handles invalid epoch seconds gracefully in rescue path' do
        # Create an object that responds to to_i but breaks Time.at
        bad_timestamp = Object.new
        def bad_timestamp.to_i
          raise ArgumentError, "Can't convert"
        end

        error = described_class.new(
          'Test error',
          nil,
          file_path:     'test.rb',
          file_mtime:    Time.at(1000),
          cov_timestamp: bad_timestamp,
          src_len:       10,
          cov_len:       8
        )

        message = error.user_friendly_message
        expect(message).to include('Coverage data stale', 'Test error')
      end

      it 'handles time that breaks Time.parse but has valid to_s' do
        # Create an object that can't be parsed but has valid to_s
        bad_time = Object.new
        def bad_time.to_s
          'unparseable_time_string'
        end

        error = described_class.new(
          'Test error',
          nil,
          file_path:     'test.rb',
          file_mtime:    bad_time,
          cov_timestamp: 1000,
          src_len:       10,
          cov_len:       8
        )

        message = error.user_friendly_message
        # Should fallback to string representation
        expect(message).to include('Coverage data stale', 'Test error', 'unparseable_time_string')
      end

      it 'handles delta calculation with invalid values in rescue path' do
        # Create objects that break arithmetic
        bad_time = Object.new
        def bad_time.to_i
          raise ArgumentError, "Can't convert"
        end

        bad_timestamp = Object.new
        def bad_timestamp.to_i
          raise ArgumentError, "Can't convert"
        end

        error = described_class.new(
          'Test error',
          nil,
          file_path:     'test.rb',
          file_mtime:    bad_time,
          cov_timestamp: bad_timestamp,
          src_len:       10,
          cov_len:       8
        )

        message = error.user_friendly_message
        expect(message).to include('Coverage data stale')
        # Delta line should not appear when calculation fails
        expect(message).not_to match(/Delta\s+- file is/)
      end
    end

    describe 'default message generation' do
      it 'uses default message when message is nil with file_path' do
        error = described_class.new(
          nil, # No message provided - triggers default_message
          nil,
          file_path:     'test.rb',
          file_mtime:    Time.at(2000),
          cov_timestamp: 1000
        )

        message = error.user_friendly_message
        # default_message returns "Coverage data appears stale for test.rb"
        expect(message).to include('Coverage data appears stale for test.rb')
        # File path should appear in the details section
        expect(message).to match(/File\s+-/)
      end

      it 'uses generic default message when file_path is nil' do
        # This tests the fallback path when file_path is nil: fp = file_path || 'file'
        error = described_class.new(
          nil, # No message - triggers default_message
          nil,
          file_path:     nil, # No file path - triggers 'file' fallback
          file_mtime:    Time.at(2000),
          cov_timestamp: 1000
        )

        message = error.user_friendly_message
        # When file_path is nil, default_message returns "Coverage data appears stale for file"
        expect(message).to include('Coverage data appears stale for file')
      end
    end
  end

  describe CovLoupe::CoverageDataProjectStaleError do
    describe 'default message generation' do
      # These tests exercise the private default_message method
      it 'includes project stale info when message is nil' do
        error = described_class.new(
          nil, # StandardError sets message to class name when nil
          nil,
          cov_timestamp: 1000,
          newer_files:   %w[file1.rb file2.rb]
        )

        message = error.user_friendly_message
        # user_friendly_message prefixes with "Coverage data stale (project):"
        expect(message).to include('Coverage data stale (project)', 'Newer files')
      end

      it 'exercises default_message directly via send' do
        # Directly test the private default_message method for coverage
        # This is necessary because user_friendly_message uses `message || default_message`
        # and StandardError sets message to class name when initialized with nil
        error = described_class.new(
          'explicit message',
          nil,
          cov_timestamp: 1000
        )

        # Call the private default_message method directly
        result = error.send(:default_message)
        expect(result).to eq('Coverage data appears stale for project')
      end
    end

    describe 'large file list truncation' do
      [
        {
          type:  :deleted,
          key:   :deleted_files,
          desc:  'deleted or moved in project',
          label: 'Coverage-only files',
        },
        {
          type:  :missing,
          key:   :missing_files,
          desc:  'new in project, not in coverage',
          label: 'Missing files',
        },
        {
          type:  :newer,
          key:   :newer_files,
          desc:  nil, # newer_files doesn't have a description in the header line
          label: 'Newer files',
        },
      ].each do |file_type|
        it "shows all files when there are 10 or fewer #{file_type[:type]} files" do
          files = (1..10).map { |i| "#{file_type[:type]}_file_#{i}.rb" }
          error_params = {
            cov_timestamp: 1000,
            file_type[:key] => files,
          }
          error = described_class.new('Test error', nil, **error_params)

          message = error.user_friendly_message
          header = if file_type[:desc]
            "#{file_type[:label]} (#{file_type[:desc]}, 10):"
          else
            "#{file_type[:label]} (10):"
          end
          expect(message).to include(header)
          expect_listed_files(message, files)
          expect(message).not_to include('...')
        end

        it "truncates and shows ellipsis when there are more than 10 #{file_type[:type]} files" do
          count = 15
          files = (1..count).map { |i| "#{file_type[:type]}_file_#{i}.rb" }
          error_params = {
            cov_timestamp: 1000,
            file_type[:key] => files,
          }
          error = described_class.new('Test error', nil, **error_params)

          message = error.user_friendly_message
          header = if file_type[:desc]
            "#{file_type[:label]} (#{file_type[:desc]}, #{count}):"
          else
            "#{file_type[:label]} (#{count}):"
          end
          expect(message).to include(header)
          # Should show first 10 files
          expect_listed_files(message, files[0..9])
          # Should not show files beyond 10
          expect_absent_files(message, files[10..14])
          # Should show ellipsis
          expect(message).to include('...')
        end
      end
    end
  end

  describe CovLoupe::CorruptCoverageDataError do
    describe '#user_friendly_message' do
      it 'returns the correct message for corrupt coverage data' do
        error = described_class.new('Invalid JSON format')
        expect(error.user_friendly_message).to eq('Corrupt coverage data: Invalid JSON format')
      end
    end
  end
end
