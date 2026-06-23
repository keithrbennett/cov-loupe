# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP Mode Logging' do
  it 'exits with an error when --log-file is stdout' do
    argv = %w[--mode mcp --log-file stdout]

    _stdout, stderr, status = run_full_cli_with_status(argv)
    expect(status).to eq(2)
    expect(stderr).to include('stdout', 'not permitted')
  end

  it 'allows stderr logging in MCP mode' do
    argv = %w[--mode mcp --log-file stderr]
    original_target = CovLoupe.active_log_file

    # The server would normally start here; stub it so we can capture the context without side effects.
    mcp_server_double = instance_double(CovLoupe::MCPServer, run: true)
    captured_context = nil
    allow(CovLoupe::MCPServer).to receive(:new) do |context:|
      # Record the context that the MCP server receives to ensure the log target was honored.
      captured_context = context
      mcp_server_double
    end

    expect do
      CovLoupe.run(argv)
    end.not_to raise_error

    # Server boot should have been given a context that points stdout logging to stderr.
    expect(captured_context).not_to be_nil
    expect(captured_context.log_target).to eq('stderr')
    # After the run, the original active context should be restored.
    expect(CovLoupe.active_log_file).to eq(original_target)
  end
end
