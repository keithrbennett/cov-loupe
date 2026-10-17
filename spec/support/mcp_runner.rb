# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'json'

module Spec
  module Support
    module McpRunner
      # Thin wrapper around `Open3.popen3` that standardizes how the integration
      # specs talk to the `cov-loupe` executable. It accepts either a single
      # JSON-RPC request hash, a sequence of requests, or raw string input,
      # writes them to the subprocess stdin (ensuring a trailing newline), then
      # collects stdout, stderr, and the exit status with a timeout. The helper
      # always returns a hash containing those streams plus the `Process::Status`
      # so callers can make assertions without duplicating the boilerplate.

      module_function def call(requests: nil, input: nil, env: {}, lib_path:, exe_path:,
        timeout: INTEGRATION_TIMEOUT, close_stdin: true)
        payload = build_payload(requests, input)

        stdout_str = ''
        stderr_str = ''
        status = nil

        cmd = ['bundle', 'exec', 'ruby', '-I', lib_path, exe_path]

        Open3.popen3(env, *cmd) do |stdin, stdout, stderr, wait_thr|
          unless payload.nil?
            stdin.write(payload)
            stdin.write("\n") if !payload.empty? && !payload.end_with?("\n")
          end
          stdin.close if close_stdin

          Timeout.timeout(timeout) do
            stdout_str = stdout.read
            stderr_str = stderr.read
            status = wait_thr.value
          end
        rescue Timeout::Error
          # popen3's ensure waits for the child without a limit, so end it before leaving.
          begin
            Process.kill('KILL', wait_thr.pid)
          rescue Errno::ESRCH
            # already exited
          end
          raise
        end

        { stdout: stdout_str, stderr: stderr_str, status: status }
      rescue Timeout::Error
        raise "MCP server timed out after #{timeout} seconds"
      end

      module_function def call_json(request_hash, input: nil, env: {}, lib_path:, exe_path:,
        timeout: INTEGRATION_TIMEOUT, close_stdin: true)
        call(requests: request_hash, input: input, env: env, lib_path: lib_path,
          exe_path: exe_path, timeout: timeout, close_stdin: close_stdin)
      end

      module_function def call_json_stream(request_hashes, input: nil, env: {}, lib_path:,
        exe_path:, timeout: INTEGRATION_TIMEOUT, close_stdin: true)
        call(requests: Array(request_hashes), input: input, env: env, lib_path: lib_path,
          exe_path: exe_path, timeout: timeout, close_stdin: close_stdin)
      end

      module_function def build_payload(requests, input)
        return input unless requests

        normalized = requests.is_a?(Array) ? requests : [requests]
        normalized.map { |req| req.is_a?(String) ? req : JSON.generate(req) }.join("\n")
      end
      private_class_method :build_payload
    end
  end
end
