# frozen_string_literal: true

require 'time'

module CovLoupe
  # Shared timestamp handling for coverage file loaders.
  #
  # Timestamps are normalized to integer epoch seconds. Missing or
  # unparseable timestamps default to 0, which disables time-based
  # staleness checks. Includers must provide a @logger.
  module TimestampNormalization
    private def normalize_coverage_timestamp(timestamp_value, created_at_value)
      raw = timestamp_value.nil? ? created_at_value : timestamp_value
      return log_missing_timestamp if raw.nil?

      timestamp = case raw
                  when Integer
                    raw
                  when Float, Time
                    raw.to_i
                  when String
                    str = raw.strip
                    # Matches optional leading "-", digits, and an optional fractional part.
                    if str.match?(/\A-?\d+(\.\d+)?\z/)
                      # Some resultsets serialize the epoch as a numeric string instead of
                      # a JSON number. Non-numeric, non-empty strings are handled by the
                      # else branch below via Time.parse.
                      str.to_f.to_i
                    elsif str.empty?
                      0
                    else
                      Time.parse(str).to_i
                    end
                  else
                    log_timestamp_warning(raw)
                    return 0
      end

      timestamp = [timestamp.to_i, 0].max # change negative numbers to zero
      log_missing_timestamp(raw) if timestamp.zero? # but log the original value
      timestamp
    rescue => e
      log_timestamp_warning(raw, e)
      0
    end

    private def log_missing_timestamp(raw_value = nil)
      message = 'Coverage timestamp missing, defaulting to 0. ' \
                'Time-based staleness checks will be disabled.'
      message = "#{message} (value: #{raw_value.inspect})" if raw_value
      @logger.safe_log(message)
      0
    end

    private def log_timestamp_warning(raw_value, error = nil)
      message = "Coverage timestamp could not be parsed: #{raw_value.inspect}"
      message = "#{message} (#{error.message})" if error
      @logger.safe_log(message)
    end
  end
end
