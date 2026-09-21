# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Thread Safety' do
  describe 'Global Configuration' do
    before do
      # Stub logger creation to prevent file creation during thread safety tests
      mock_logger = instance_double(
        CovLoupe::Logger, info: nil, warn: nil, error: nil, safe_log: nil)
      allow(CovLoupe::Logger).to receive(:new).and_return(mock_logger)
    end

    it 'handles concurrent default_log_file= safely' do
      # Reset state
      CovLoupe.default_log_file = nil

      threads = 10.times.map do |i|
        Thread.new do
          100.times do
            CovLoupe.default_log_file = "log-#{i}.txt"
            expect(CovLoupe.default_log_file).to match(/log-\d+\.txt/)
          end
        end
      end
      threads.each(&:join)

      # Reset to avoid file creation in spec_helper's after hook
      CovLoupe.default_log_file = File::NULL
    end

    it 'handles concurrent error_handler= safely' do
      # Reset state
      initial_handler = CovLoupe.error_handler
      handlers = 10.times.map { Object.new }

      threads = handlers.map do |handler|
        Thread.new do
          100.times do
            CovLoupe.error_handler = handler
            # Whichever thread wrote last, the reader must return one of the handlers
            # that was assigned, never the initial handler or a partial value.
            expect(handlers).to include(CovLoupe.error_handler)
          end
        end
      end
      threads.each(&:join)

      # Restore
      CovLoupe.error_handler = initial_handler
    end

    it 'does not lose an update when different settings change concurrently' do
      initial_handler = CovLoupe.error_handler
      handler = Object.new

      # Each setter reads the current context and then replaces it. Widen that
      # read-modify-write window so a missing lock would let one update overwrite the other.
      allow(CovLoupe).to receive(:internal_default_context).and_wrap_original do |original|
        context = original.call
        sleep 0.01
        context
      end

      [
        Thread.new { CovLoupe.default_log_file = 'concurrent.log' },
        Thread.new { CovLoupe.error_handler = handler },
      ].each(&:join)

      # The setters change the shared default context; read the handler from a thread
      # with no context of its own, since the test thread may have one that takes precedence.
      default_handler = Thread.new { CovLoupe.error_handler }.value

      aggregate_failures do
        expect(CovLoupe.default_log_file).to eq('concurrent.log')
        expect(default_handler).to be(handler)
      end

      # Restore to avoid leaking state and file creation in spec_helper's after hook
      CovLoupe.error_handler = initial_handler
      CovLoupe.default_log_file = File::NULL
    end

    it 'isolates thread-local active_log_file changes' do
      CovLoupe.default_log_file = 'default.log'

      t1 = Thread.new do
        CovLoupe.active_log_file = 'thread1.log'
        sleep 0.1
        expect(CovLoupe.active_log_file).to eq('thread1.log')
        expect(CovLoupe.default_log_file).to eq('default.log')
      end

      t2 = Thread.new do
        CovLoupe.active_log_file = 'thread2.log'
        sleep 0.1
        expect(CovLoupe.active_log_file).to eq('thread2.log')
        expect(CovLoupe.default_log_file).to eq('default.log')
      end

      t1.join
      t2.join

      expect(CovLoupe.default_log_file).to eq('default.log')

      # Reset to avoid file creation in spec_helper's after hook
      CovLoupe.default_log_file = File::NULL
    end
  end
end
