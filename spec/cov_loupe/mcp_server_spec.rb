# frozen_string_literal: true

require 'spec_helper'
require 'support/fake_mcp'

RSpec.describe CovLoupe::MCPServer do
  # This spec verifies the MCP server boot path without requiring the real
  # MCP runtime. We stub the MCP::Server and its stdio transport to capture
  # constructor parameters and observe that `open` is invoked.
  it 'sets error handler and boots server with expected tools' do
    # Prepare fakes for MCP server and transport
    module ::MCP; end unless defined?(::MCP)

    stub_const('MCP::Server', FakeMCP::Server)
    stub_const('MCP::Server::Transports::StdioTransport', FakeMCP::StdioTransport)

    server_context = CovLoupe.create_context(
      error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
      log_target:    'stderr',
      app_config:    CovLoupe::AppConfig.new(allow_code_predicates: true)
    )
    server = described_class.new(context: server_context)
    baseline_context = CovLoupe.context

    # Run should construct server and open transport
    server.run
    # Server should restore the caller's context after execution.
    expect(CovLoupe.context).to eq(baseline_context)

    # Fetch the instances created during `run` via the class-level hooks.
    fake_server = FakeMCP::Server.last_instance
    fake_transport = FakeMCP::StdioTransport.last_instance

    expect(fake_transport).not_to be_nil
    expect(fake_transport).to be_opened
    expect(fake_server).not_to be_nil

    expect(fake_server.params[:name]).to eq('cov-loupe')
    # Ensure instructions mention the README path
    expect(fake_server.params[:instructions]).to include('README.md')
    # Ensure expected tools are registered
    tool_names = fake_server.params[:tools].map { |t| t.name.split('::').last }
    expect(tool_names).to include(
      'ProjectCoverageTool',
      'FileCoverageDetailedTool',
      'FileCoverageRawTool',
      'FileCoverageSummaryTool',
      'ProjectCoverageTotalsTool',
      'FileUncoveredLinesTool',
      'ProjectValidateTool',
      'HelpTool',
      'VersionTool'
    )
  end

  describe '#toolset' do
    [
      { app_config: nil, includes_validate: false },
      { app_config: CovLoupe::AppConfig.new, includes_validate: false },
      { app_config: CovLoupe::AppConfig.new(allow_code_predicates: true), includes_validate: true },
    ].each do |tc|
      it "#{tc[:includes_validate] ? 'includes' : 'omits'} ProjectValidateTool when " \
         "allow_code_predicates is #{tc[:app_config]&.allow_code_predicates.inspect}" do
        context = CovLoupe.create_context(
          error_handler: CovLoupe::ErrorHandlerFactory.for_mcp_server,
          app_config:    tc[:app_config]
        )
        toolset = described_class.new(context: context).toolset

        expect(toolset.include?(CovLoupe::Tools::ProjectValidateTool)).to be(tc[:includes_validate])
        expect(toolset).to include(*(described_class::TOOLSET - [CovLoupe::Tools::ProjectValidateTool]))
      end
    end
  end

  describe 'TOOLSET and TOOL_GUIDE consistency' do
    it 'includes all tools documented in HelpTool TOOL_GUIDE' do
      # Get tool classes from TOOLSET
      toolset_classes = described_class::TOOLSET

      # Get tool classes from TOOL_GUIDE
      tool_guide_classes = CovLoupe::Tools::HelpTool::TOOL_GUIDE.map { |guide| guide[:tool] }

      # Every tool in TOOL_GUIDE should be in TOOLSET
      tool_guide_classes.each do |tool_class|
        expect(toolset_classes).to include(tool_class),
          "Expected TOOLSET to include #{tool_class.name}, but it was missing. " \
            'Add it to MCPServer::TOOLSET or remove from HelpTool::TOOL_GUIDE.'
      end
    end

    it 'has corresponding TOOL_GUIDE entry for all tools (except HelpTool itself)' do
      toolset_classes = described_class::TOOLSET
      tool_guide_classes = CovLoupe::Tools::HelpTool::TOOL_GUIDE.map { |guide| guide[:tool] }

      # Every tool in TOOLSET should be in TOOL_GUIDE (except HelpTool which documents itself)
      toolset_classes.each do |tool_class|
        # HelpTool doesn't need an entry about itself
        next if tool_class == CovLoupe::Tools::HelpTool

        expect(tool_guide_classes).to include(tool_class),
          "Expected TOOL_GUIDE to document #{tool_class.name}, but it was missing. " \
            'Add documentation for this tool to HelpTool::TOOL_GUIDE.'
      end
    end

    it 'lists the expected number of tools in TOOLSET, before #toolset filtering' do
      expect(described_class::TOOLSET.length).to eq(9)
    end

    it 'registers all tool classes defined in CovLoupe::Tools module' do
      # This test catches the bug where a tool file is created, required in
      # cov_loupe.rb, but not added to MCPServer::TOOLSET.
      #
      # Get all classes in the Tools module that inherit from BaseTool
      tool_classes = CovLoupe::Tools.constants
        .map { |const_name| CovLoupe::Tools.const_get(const_name) }
        .select { |const| const.is_a?(Class) && const < CovLoupe::BaseTool }

      toolset_classes = described_class::TOOLSET

      tool_classes.each do |tool_class|
        expect(toolset_classes).to include(tool_class),
          "Expected TOOLSET to include #{tool_class.name}, but it was missing. " \
            'The tool class exists in CovLoupe::Tools but is not registered in MCPServer::TOOLSET.'
      end
    end
  end
end
