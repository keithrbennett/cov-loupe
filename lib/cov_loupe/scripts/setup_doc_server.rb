# frozen_string_literal: true

require_relative 'command_execution'

module CovLoupe
  module Scripts
    class SetupDocServer
      include CommandExecution

      VENV_DIR = '.docs-venv'

      def call
        puts 'Setting up Python virtual environment...'
        run_command(['python3', '-m', 'venv', VENV_DIR], print_output: true)

        puts 'Installing dependencies...'
        pip_path = File.join(VENV_DIR, 'bin', 'pip')
        requirements_path = if File.exist?('requirements-lock.txt')
          'requirements-lock.txt'
        else
          'requirements.txt'
        end
        run_command([pip_path, 'install', '-q', '-r', requirements_path], print_output: true)

        puts '✓ Documentation server setup complete.'
      end
    end
  end
end
