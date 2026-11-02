# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/model/coverage_row_sorter'

RSpec.describe CovLoupe::CoverageRowSorter do
  let(:root) { File.expand_path('/proj') }
  let(:rows) do
    [
      { 'file' => 'lib/b.rb', 'percentage' => 50.0 },
      { 'file' => 'lib/none.rb', 'percentage' => nil },
      { 'file' => 'lib/full.rb', 'percentage' => 100.0 },
      # A relative and an absolute path tie on percentage; both break ties by absolute path.
      { 'file' => File.join(root, 'lib/c.rb'), 'percentage' => 50.0 },
      { 'file' => 'lib/a.rb', 'percentage' => 50.0 },
      { 'file' => 'lib/zero.rb', 'percentage' => 0.0 },
    ]
  end

  def sorted_files(sort_order)
    described_class.sort(rows, sort_order: sort_order, root: root).map { |row| File.basename(row['file']) }
  end

  [
    [:descending, %w[none.rb full.rb a.rb b.rb c.rb zero.rb]],
    [:ascending,  %w[zero.rb a.rb b.rb c.rb full.rb none.rb]],
  ].each do |sort_order, expected|
    it "sorts #{sort_order}, keeping nil percentages above 100% and breaking ties by absolute path" do
      expect(sorted_files(sort_order)).to eq(expected)
    end
  end

  it 'returns a new array without reordering the input' do
    original = rows.dup
    described_class.sort(rows, sort_order: :ascending, root: root)
    expect(rows).to eq(original)
  end
end
