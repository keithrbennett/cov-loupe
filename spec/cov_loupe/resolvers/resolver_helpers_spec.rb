# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe CovLoupe::Resolvers::ResolverHelpers do
  describe '.create_coverage_resolver' do
    it 'wraps coverage data in a CoverageLineResolver' do
      cov = { '/tmp/foo.rb' => { 'lines' => [1, 0] } }
      resolver = described_class.create_coverage_resolver(
        cov, root: '/tmp', volume_case_sensitive: true)

      expect(resolver).to be_a(CovLoupe::Resolvers::CoverageLineResolver)
      expect(resolver.lookup_lines('/tmp/foo.rb')).to eq([1, 0])
    end
  end

  describe '.find_coverage_file' do
    it 'locates the default coverage file within the provided root' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'coverage'))
        coverage_file_path = File.join(dir, 'coverage', 'coverage.json')
        File.write(coverage_file_path, '{}')

        resolved = described_class.find_coverage_file(dir)

        expect(resolved).to eq(coverage_file_path)
      end
    end
  end

  describe '.lookup_lines' do
    it 'delegates to CoverageLineResolver for lookups' do
      cov = { '/tmp/bar.rb' => { 'lines' => [0, 1] } }

      expect(
        described_class.lookup_lines(cov, '/tmp/bar.rb', root: '/tmp', volume_case_sensitive: true)
      ).to eq([0, 1])
    end

    it 'passes root parameter to CoverageLineResolver' do
      cov = { 'lib/foo.rb' => { 'lines' => [1, 1] } }
      root = '/my/root'
      abs_path = '/my/root/lib/foo.rb'

      # If root is passed, it should find it via stripping root
      expect(
        described_class.lookup_lines(cov, abs_path, root: root, volume_case_sensitive: true)
      ).to eq([1, 1])
    end
  end
end
