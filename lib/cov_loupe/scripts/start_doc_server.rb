# frozen_string_literal: true

require_relative 'command_execution'
require_relative 'setup_doc_server'

module CovLoupe
  module Scripts
    class StartDocServer
      include CommandExecution

      VENV_DIR = '.docs-venv'

      def call
        mkdocs_path = resolve_mkdocs_path

        unless command_exists?(mkdocs_path)
          warn "Error: mkdocs not found. Please run 'bin/set-up-python-for-doc-server' or " \
               "'rake docs:setup' first."
          exit 1
        end

        puts 'Starting documentation server...'
        $stdout.flush
        exec(mkdocs_path, 'serve')
      end

      private def resolve_mkdocs_path
        return 'mkdocs' if command_exists?('mkdocs')

        mkdocs_path = File.join(VENV_DIR, 'bin', 'mkdocs')
        return mkdocs_path if command_exists?(mkdocs_path)

        puts 'Documentation virtual environment not found; setting it up...'
        SetupDocServer.new.call
        mkdocs_path
      end
    end
  end
end
