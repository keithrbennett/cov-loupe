# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/scripts/setup_doc_server'

# rubocop:disable RSpec/SubjectStub
RSpec.describe CovLoupe::Scripts::SetupDocServer do
  subject(:script) { described_class.new }

  describe '#call' do
    before do
      allow($stdout).to receive(:puts)
      allow($stdout).to receive(:warn)
      allow(script).to receive(:run_command_with_status)
        .with(described_class::PYTHON_VERSION_CHECK).and_return(['', true])
    end

    it 'aborts before creating the venv when python3 is older than 3.11 or missing' do
      allow(script).to receive(:run_command_with_status)
        .with(described_class::PYTHON_VERSION_CHECK).and_return(['', false])
      allow(script).to receive(:abort_with).and_raise(SystemExit)
      allow(script).to receive(:run_command)

      expect { script.call }.to raise_error(SystemExit)
      expect(script).to have_received(:abort_with).with(/Python 3\.11 or newer/)
      expect(script).not_to have_received(:run_command)
    end

    it 'creates a docs venv and installs locked dependencies' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('requirements-lock.txt').and_return(true)

      expect(script).to receive(:run_command).with(%w[python3 -m venv .docs-venv], print_output: true)

      expect(script).to receive(:run_command).with(
        %w[.docs-venv/bin/pip install -q -r requirements-lock.txt],
        print_output: true
      )

      script.call
      expect($stdout).to have_received(:puts).with(/setup complete/)
    end

    it 'fails gracefully if pip install fails' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('requirements-lock.txt').and_return(true)
      allow(script).to receive(:run_command).with(%w[python3 -m venv .docs-venv], print_output: true)

      allow(script).to receive(:run_command).with(
        %w[.docs-venv/bin/pip install -q -r requirements-lock.txt],
        print_output: true
      ).and_raise(SystemExit)

      expect { script.call }.to raise_error(SystemExit)
    end

    it 'falls back to requirements.txt if no lock file exists' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('requirements-lock.txt').and_return(false)
      allow(script).to receive(:run_command).with(%w[python3 -m venv .docs-venv], print_output: true)

      expect(script).to receive(:run_command).with(
        %w[.docs-venv/bin/pip install -q -r requirements.txt],
        print_output: true
      )

      script.call
    end
  end
end
# rubocop:enable RSpec/SubjectStub
