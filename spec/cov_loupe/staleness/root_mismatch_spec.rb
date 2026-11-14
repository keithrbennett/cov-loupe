# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe CovLoupe::RootMismatch do
  def message(deleted_count: 2, total_count: 2, root: '/wrong', recorded_root: nil)
    described_class.message(deleted_count: deleted_count, total_count: total_count, root: root) do
      recorded_root
    end
  end

  [[2, 2], [2, 3]].each do |deleted_count, total_count|
    it "warns when #{deleted_count} of #{total_count} files were not found" do
      expect(message(deleted_count: deleted_count, total_count: total_count))
        .to include("(#{deleted_count} of #{total_count})", '/wrong', '--root')
    end
  end

  [[0, 0], [0, 2], [1, 2]].each do |deleted_count, total_count|
    it "does not warn when #{deleted_count} of #{total_count} files were not found" do
      expect(message(deleted_count: deleted_count, total_count: total_count)).to be_nil
    end
  end

  describe 'recorded root' do
    let(:suggestion) { 'The coverage file was generated with root' }

    it 'names a recorded root that exists and differs from the root' do
      Dir.mktmpdir do |dir|
        expect(message(recorded_root: dir)).to end_with("#{suggestion} #{File.expand_path(dir)}.")
      end
    end

    it 'omits a recorded root that does not exist here' do
      expect(message(recorded_root: '/no/such/ci/checkout')).not_to include(suggestion)
    end

    it 'does not ask for the recorded root when there is no warning' do
      expect do |block|
        described_class.message(deleted_count: 0, total_count: 2, root: '/wrong', &block)
      end.not_to yield_control
    end

    it 'omits a recorded root equal to the root' do
      Dir.mktmpdir do |dir|
        expect(message(root: dir, recorded_root: dir)).not_to include(suggestion)
      end
    end
  end
end
