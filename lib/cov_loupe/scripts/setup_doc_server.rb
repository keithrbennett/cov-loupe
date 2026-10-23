# frozen_string_literal: true

require_relative 'command_execution'

module CovLoupe
  module Scripts
    # @api private
    class SetupDocServer
      include CommandExecution

      VENV_DIR = '.docs-venv'
      PYTHON_VERSION_CHECK = ['python3', '-c', 'import sys; sys.exit(sys.version_info < (3, 11))'].freeze

      def call
        _output, supported = run_command_with_status(PYTHON_VERSION_CHECK)
        unless supported
          abort_with('The documentation tools require Python 3.11 or newer, and python3 is older or ' \
            'missing. Install Python 3.11 or newer, make sure python3 resolves to it, and run this again.')
        end

        puts 'Setting up Python virtual environment...'
        run_command(['python3', '-m', 'venv', VENV_DIR], print_output: true)

        puts 'Installing dependencies...'
        install_dependencies

        puts '✓ Documentation server setup complete.'
      end

      # Installs the locked dependencies into an existing venv. When every pin is already
      # satisfied this is quick and needs no network access.
      def install_dependencies
        pip_path = File.join(VENV_DIR, 'bin', 'pip')
        requirements_path = if File.exist?('requirements-lock.txt')
          'requirements-lock.txt'
        else
          'requirements.txt'
        end
        run_command([pip_path, 'install', '-q', '-r', requirements_path], print_output: true)
      end
    end
  end
end
