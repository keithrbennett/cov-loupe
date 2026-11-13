# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::RootMismatch do
  [[2, 2], [2, 3]].each do |deleted_count, total_count|
    it "warns when #{deleted_count} of #{total_count} files were not found" do
      message = described_class.message(deleted_count: deleted_count, total_count: total_count,
        root: '/wrong')

      expect(message).to include("(#{deleted_count} of #{total_count})", '/wrong', '--root')
    end
  end

  [[0, 0], [0, 2], [1, 2]].each do |deleted_count, total_count|
    it "does not warn when #{deleted_count} of #{total_count} files were not found" do
      expect(described_class.message(deleted_count: deleted_count, total_count: total_count,
        root: '/wrong')).to be_nil
    end
  end
end
