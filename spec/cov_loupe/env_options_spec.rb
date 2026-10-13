# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe do
  describe '.run' do
    context 'with invalid COV_LOUPE_OPTS' do
      it 'exits with code 2 and shows a friendly error message' do
        allow(ENV).to receive(:[]).with('COV_LOUPE_OPTS').and_return('invalid " quote')

        expect do
          expect { described_class.run([]) }.to raise_error(SystemExit) do |error|
            expect(error.status).to eq(2)
          end
        end.to output(/Error: Invalid COV_LOUPE_OPTS format/).to_stderr
      end
    end

    context 'with valid COV_LOUPE_OPTS' do
      it 'merges options and runs correctly' do
        allow(ENV).to receive(:[]).with('COV_LOUPE_OPTS').and_return('--mode cli')

        cli = instance_double(described_class::CoverageCLI, run: nil)
        allow(described_class::CoverageCLI).to receive(:new).and_return(cli)

        described_class.run(['version'])

        expect(cli).to have_received(:run).with(['--mode', 'cli', 'version'], env_arg_count: 2)
      end
    end
  end
end
