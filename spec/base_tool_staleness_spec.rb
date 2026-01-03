# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/tools/coverage_summary_tool'
require 'digest'

RSpec.describe CovLoupe::Tools::CoverageSummaryTool do
  include MCPToolTestHelpers

  let(:context) { mcp_server_context }
  let(:root) { File.absolute_path('.') }
  let(:file_path) { 'lib/foo.rb' }

  before do
    allow(CovLoupe::CoverageModel).to receive(:new).and_call_original
    # Ensure the file exists so we don't hit FileNotFoundError
    FileUtils.mkdir_p(File.dirname(file_path))
    FileUtils.touch(file_path)
    # Mock File.stat and Digest for the resultset file so ModelCache can store/fetch
    resultset_path = File.join(root, 'coverage', '.resultset.json')
    stat = double('File::Stat', mtime: Time.now, size: 1000, ino: 12_345)
    allow(File).to receive(:stat).and_call_original
    allow(File).to receive(:stat).with(resultset_path).and_return(stat)
    allow(Digest::MD5).to receive(:file).and_call_original
    allow(Digest::MD5).to receive(:file).with(resultset_path)
      .and_return(double(hexdigest: 'test_digest'))
  end

  after do
    FileUtils.rm_f(file_path)
  end

  def fetch_cached_model(context)
    config = { root: '.', resultset: nil }
    context.model_cache.fetch(config)
  end

  it 'overrides cached model default raise_on_stale when true is passed' do
    mock_resultset_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP)

    # 1. First call: raise_on_stale: false (default)
    described_class.call_with_file_payload(
      path: file_path,
      error_mode: 'log',
      server_context: context,
      raise_on_stale: false
    )

    cached_model = fetch_cached_model(context)
    expect(cached_model).not_to be_nil

    # Mock summary_for to return dummy data
    allow(cached_model).to receive(:summary_for).and_return(
      { 'file' => file_path, 'summary' => { 'covered' => 0, 'total' => 0, 'percent_covered' => 0.0 } }
    )

    # 2. Second call: raise_on_stale: true
    described_class.call_with_file_payload(
      path: file_path,
      error_mode: 'log',
      server_context: context,
      raise_on_stale: true
    )

    # Verify override
    expect(cached_model).to have_received(:summary_for)
      .with(file_path, hash_including(raise_on_stale: true))
  end

  it 'passes raise_on_stale: false correctly even if model default differs' do
    mock_resultset_with_timestamp(root, FIXTURE_COVERAGE_TIMESTAMP)

    # 1. Prime cache with a "strict" model (simulate by passing true first)
    described_class.call_with_file_payload(
      path: file_path,
      error_mode: 'log',
      server_context: context,
      raise_on_stale: true
    )

    cached_model = fetch_cached_model(context)
    allow(cached_model).to receive(:summary_for).and_return(
      { 'file' => file_path, 'summary' => { 'covered' => 0, 'total' => 0, 'percent_covered' => 0.0 } }
    )

    # 2. Second call: raise_on_stale: false
    described_class.call_with_file_payload(
      path: file_path,
      error_mode: 'log',
      server_context: context,
      raise_on_stale: false
    )

    # Verify override
    expect(cached_model).to have_received(:summary_for)
      .with(file_path, hash_including(raise_on_stale: false))
  end
end
