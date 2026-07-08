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
