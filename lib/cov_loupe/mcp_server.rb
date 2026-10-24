# frozen_string_literal: true

require_relative 'resources'

# JSON-RPC server exposing coverage data tools via the Model Context Protocol (MCP).
#
# Runs on stdio, making it suitable for editor/agent integrations (e.g., Claude, VS Code).
# Each tool call builds its own CoverageModel and relies on ModelDataCache for shared
# coverage data, so request-specific state does not leak across calls.
#
# The TOOLSET constant lists every tool; #toolset, which the server registers, omits those
# that execute client-supplied code (project_validate) unless --allow-code-predicates was
# given at startup. Each tool class inherits from BaseTool, which provides shared error
# handling, JSON response formatting, and model configuration merging from the server
# context plus per-call arguments.
module CovLoupe
  # @api private
  class MCPServer
    def initialize(context: CovLoupe.context)
      @context = context
    end

    def run
      CovLoupe.with_context(context) do
        server = ::MCP::Server.new(
          name:           'cov-loupe',
          version:        CovLoupe::VERSION,
          tools:          toolset,
          instructions:   instructions,
          server_context: context
        )
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        use_utf8_stdio
        transport.open
      end
    end

    # The transport sets only the external encoding of stdin and stdout, so when
    # Encoding.default_internal is set (RUBYOPT=-U or -E) reads are still transcoded into it, and a
    # request with non-ASCII characters crashes the server or loses its UTF-8. JSON-RPC over stdio
    # is UTF-8, so read and write it with no transcoding, as cov-loupe reads its files. The same
    # goes for stderr, where the log lines can name non-ASCII paths.
    private def use_utf8_stdio
      [$stdin, $stdout, $stderr].each { |io| io.set_encoding(Encoding::UTF_8, Encoding::UTF_8) }
    end

    # Every tool class; #toolset is the subset actually registered, in this order.
    # (The help tool's listing follows HelpTool::TOOL_GUIDE.)
    # File-scope tools require a `path` argument; project-scope tools do not.
    TOOLSET = [
      Tools::ProjectCoverageTool,
      Tools::FileCoverageDetailedTool,
      Tools::FileCoverageRawTool,
      Tools::FileCoverageSummaryTool,
      Tools::ProjectCoverageTotalsTool,
      Tools::FileUncoveredLinesTool,
      Tools::ProjectValidateTool,
      Tools::HelpTool,
      Tools::VersionTool,
    ].freeze

    # Expose the registered tools so embedders can introspect without booting the server.
    # Tools that execute client-supplied code are omitted unless --allow-code-predicates was given.
    def toolset
      TOOLSET.select { |tool| tool.available_in?(context) }
    end

    attr_reader :context

    private def instructions
      <<~MSG.chomp
        cov-loupe provides SimpleCov coverage data via MCP tools.
        Documentation resources: #{JSON.generate(Resources::RESOURCE_MAP)}
        Call help for tool usage guidance. File-scope tools (file_coverage_*, file_uncovered_lines) require a path argument; project-scope tools (project_*) do not.
        Coverage tools (all but help and version) accept optional `root` (project root directory) and `coverage_file`
        (path to coverage.json or a directory containing it) arguments when the defaults
        need overriding; these may point to different locations.
      MSG
    end
  end
end
