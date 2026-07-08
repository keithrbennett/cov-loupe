# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/scripts/start_doc_server'

# rubocop:disable RSpec/SubjectStub
RSpec.describe CovLoupe::Scripts::StartDocServer do
  subject(:script) { described_class.new }

  describe '#call' do
    before do
      allow($stdout).to receive(:puts)
      allow($stdout).to receive(:warn)
      allow($stdout).to receive(:flush)
    end

    context 'when mkdocs is found globally' do
      before do
        allow(script).to receive(:command_exists?).with('mkdocs').and_return(true)
      end

      it 'executes the global mkdocs' do
        expect(script).to receive(:exec).with('mkdocs', 'serve')
        script.call
      end
    end

    context 'when mkdocs is found in the docs venv' do
      before do
        allow(script).to receive(:command_exists?).with('mkdocs').and_return(false)
        allow(script).to receive(:command_exists?).with('.docs-venv/bin/mkdocs').and_return(true)
      end

      it 'executes the venv mkdocs' do
        expect(script).to receive(:exec).with('.docs-venv/bin/mkdocs', 'serve')
        script.call
      end
    end

    context 'when mkdocs is missing before setup' do
      let(:setup_script) { instance_double(CovLoupe::Scripts::SetupDocServer, call: nil) }

      before do
        allow(script).to receive(:command_exists?).with('mkdocs').and_return(false)
        allow(script).to receive(:command_exists?).with('.docs-venv/bin/mkdocs').and_return(false, true)
        allow(CovLoupe::Scripts::SetupDocServer).to receive(:new).and_return(setup_script)
      end

      it 'sets up the docs venv and executes its mkdocs' do
        expect(script).to receive(:exec).with('.docs-venv/bin/mkdocs', 'serve')

        script.call

        expect(setup_script).to have_received(:call)
      end
    end
  end
end
# rubocop:enable RSpec/SubjectStub
