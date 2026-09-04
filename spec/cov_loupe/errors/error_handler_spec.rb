# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::ErrorHandler do
  subject(:handler) { described_class.new(error_mode: :log, logger: logger) }

  let(:logger) do
    Class.new do
      attr_reader :messages

      def initialize = @messages = []
      def error(msg) = @messages << msg
    end.new
  end

  it 'maps filesystem errors to friendly custom errors' do
    [
      { error: Errno::EISDIR.new('Is a directory'), expected: CovLoupe::NotAFileError },
      { error: Errno::ENOENT.new('No such file'), expected: CovLoupe::FileNotFoundError },
      { error: Errno::EACCES.new('Permission denied'), expected: CovLoupe::FilePermissionError },
    ].each do |tc|
      e = handler.convert_standard_error(tc[:error])
      expect(e).to be_a(tc[:expected])
    end
  end

  describe 'additional file and data error mappings' do
    [
      {
        error:    Errno::ENOSPC.new('No space left on device'),
        expected: CovLoupe::FileError,
        msg:      'No space left on device',
      },
      {
        error:    Errno::EROFS.new('Read-only file system'),
        expected: CovLoupe::FilePermissionError,
        msg:      'Read-only file system',
      },
      {
        error:    Errno::EMFILE.new('Too many open files'),
        expected: CovLoupe::FileError,
        msg:      'Too many open files',
      },
      {
        error:    IOError.new('Input/output error'),
        expected: CovLoupe::FileError,
        msg:      'Input/output error',
      },
      {
        error:    EncodingError.new('incompatible encoding'),
        expected: CovLoupe::CoverageDataError,
        msg:      'Invalid encoding in coverage data',
      },
      {
        error:    RangeError.new('float domain error'),
        expected: CovLoupe::CoverageDataError,
        msg:      'Numeric overflow or range error',
      },
    ].each do |spec|
      it "maps #{spec[:error].class} to #{spec[:expected]}" do
        e = handler.convert_standard_error(spec[:error])
        expect(e).to be_a(spec[:expected])
        expect(e.message).to include(spec[:msg])
      end
    end
  end

  it 'maps JSON::ParserError to CoverageDataError' do
    e = handler.convert_standard_error(JSON::ParserError.new('unexpected token'))
    expect(e).to be_a(CovLoupe::CoverageDataError)
    expect(e.user_friendly_message).to include('Invalid coverage data format')
  end

  it 'maps ArgumentError by message' do
    e = handler.convert_standard_error(
      ArgumentError.new('wrong number of arguments (given 1, expected 2)')
    )
    expect(e).to be_a(CovLoupe::UsageError)

    e = handler.convert_standard_error(ArgumentError.new('invalid option'))
    expect(e).to be_a(CovLoupe::ConfigurationError)
  end

  it 'maps NoMethodError to CoverageDataError with helpful info' do
    e = handler.convert_standard_error(
      NoMethodError.new("undefined method `fetch' for #<Hash:0x123>")
    )
    expect(e).to be_a(CovLoupe::CoverageDataError)
    expect(e.user_friendly_message).to include('Invalid coverage data structure')
  end

  it 'wraps RuntimeError as UnknownError' do
    error = RuntimeError.new('Could not find .resultset.json under /path; run tests')
    result = handler.convert_standard_error(error)

    expect(result).to be_a(CovLoupe::UnknownError)
    expect(result.message).to eq('Could not find .resultset.json under /path; run tests')
  end

  it 'logs via provided logger' do
    begin
      handler.handle_error(Errno::ENOENT.new('No such file or directory @ rb_sysopen - x'),
        context: 'test', reraise: false)
    rescue
      # reraise disabled
    end
    expect(logger.messages.join).to include('Error in test')
  end

  it 'converts TypeError to CoverageDataError for invalid data structures' do
    error = TypeError.new('wrong argument type')
    result = handler.convert_standard_error(error)

    expect(result).to be_a(CovLoupe::CoverageDataError)
    expect(result.user_friendly_message).to include('Invalid coverage data structure')
  end

  it 'wraps unrecognized SystemCallError as UnknownError' do
    error = Errno::EEXIST.new('File exists')
    result = handler.convert_standard_error(error)

    expect(result).to be_a(CovLoupe::UnknownError)
    expect(result.user_friendly_message).to include('An unexpected error occurred')
  end

  it 'handles NoMethodError with non-standard message format' do
    error = NoMethodError.new('some weird error message without the expected pattern')
    result = handler.convert_standard_error(error)

    expect(result).to be_a(CovLoupe::CoverageDataError)
    expect(result.user_friendly_message).to include('some weird error message')
  end

  describe 'else branch for unhandled exceptions' do
    it 'returns generic Error for unrecognized exceptions' do
      custom_exception_class = Class.new(StandardError) do
        def message
          'Custom non-standard exception'
        end
      end

      error = custom_exception_class.new
      result = handler.convert_standard_error(error)

      expect(result).to be_a(CovLoupe::Error)
      expect(result.user_friendly_message).to include('An unexpected error occurred')
      expect(result.user_friendly_message).to include('Custom non-standard exception')
    end

    it 'returns generic Error for ScriptError subclasses' do
      # ScriptError inherits from Exception, not StandardError
      error = NotImplementedError.new('This feature is not implemented')
      result = handler.convert_standard_error(error)

      expect(result).to be_a(CovLoupe::Error)
      expect(result.user_friendly_message).to include('An unexpected error occurred')
    end
  end

  describe 'extract_method_info fallback' do
    # This tests the fallback path in extract_method_info when NoMethodError
    # message doesn't match the expected pattern
    it 'returns original message when pattern does not match' do
      # Test various NoMethodError formats that won't match the regex
      test_messages = [
        'method not found',
        'private method called',
        'undefined local variable or method',
        '',
      ]

      test_messages.each do |msg|
        error = NoMethodError.new(msg)
        result = handler.convert_standard_error(error)

        expect(result).to be_a(CovLoupe::CoverageDataError)
        # The original message should be preserved
        expect(result.message).to include(msg) unless msg.empty?
      end
    end
  end

  describe 'RuntimeError handling with general context' do
    it 'wraps RuntimeError as UnknownError' do
      error = RuntimeError.new('Some completely unexpected runtime error')

      result = handler.convert_standard_error(error, context: :general)

      expect(result).to be_a(CovLoupe::UnknownError)
    end
  end

  describe '#handle_error with reraise' do
    it 're-raises CovLoupe::Error when reraise is true' do
      error = CovLoupe::FileNotFoundError.new('Test file not found')

      expect { handler.handle_error(error, context: 'test', reraise: true) }
        .to raise_error(CovLoupe::FileNotFoundError, 'Test file not found')

      # Verify it was logged
      expect(logger.messages.join).to include('Error in test')
    end

    it 'converts and re-raises StandardError when reraise is true' do
      error = Errno::ENOENT.new('No such file or directory @ rb_sysopen - missing.rb')

      expect { handler.handle_error(error, context: 'test', reraise: true) }
        .to raise_error(CovLoupe::FileNotFoundError)

      # Verify it was logged
      expect(logger.messages.join).to include('Error in test')
    end
  end

  describe '#handle_error with context parameter' do
    [
      {
        desc:     'converts Errno::ENOENT to CoverageFileNotFoundError when context is :coverage_loading',
        error:    Errno::ENOENT.new('missing .resultset.json'),
        context:  :coverage_loading,
        expected: CovLoupe::CoverageFileNotFoundError,
        msg:      'Coverage data not found',
      },
      {
        desc:     'converts Errno::ENOENT to FileNotFoundError when context is :general',
        error:    Errno::ENOENT.new('missing file'),
        context:  :general,
        expected: CovLoupe::FileNotFoundError,
      },
      {
        desc:     'converts Errno::ENOENT to FileNotFoundError when context is nil',
        error:    Errno::ENOENT.new('missing file'),
        context:  nil,
        expected: CovLoupe::FileNotFoundError,
      },
      {
        desc:     'converts Errno::EACCES with context message when context is :coverage_loading',
        error:    Errno::EACCES.new('permission denied'),
        context:  :coverage_loading,
        expected: CovLoupe::FilePermissionError,
        msg:      /Permission denied reading coverage data/,
      },
      {
        desc:     'converts ArgumentError with context message when context is :coverage_loading',
        error:    ArgumentError.new('invalid path'),
        context:  :coverage_loading,
        expected: CovLoupe::CoverageDataError,
        msg:      /Invalid path in coverage data/,
      },
      {
        desc:     'converts NoMethodError with context message when context is :coverage_loading',
        error:    NoMethodError.new("undefined method `each'"),
        context:  :coverage_loading,
        expected: CovLoupe::CoverageDataError,
        msg:      /Invalid coverage data structure/,
      },
    ].each do |tc|
      it tc[:desc] do
        expect { handler.handle_error(tc[:error], context: tc[:context], reraise: true) }
          .to raise_error(tc[:expected], tc[:msg])
      end
    end
  end
end
