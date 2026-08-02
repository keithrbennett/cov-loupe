# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CovLoupe::VERSION' do
  let(:version_file) { File.expand_path('../../lib/cov_loupe/version.rb', __dir__) }
  let(:gemspec_file) { File.expand_path('../../cov-loupe.gemspec', __dir__) }
  let(:semver_regex) do
    %r{\A
      (?<major>0|[1-9]\d*)\.
      (?<minor>0|[1-9]\d*)\.
      (?<patch>0|[1-9]\d*)
      (?:[.-](?<prerelease>[0-9A-Za-z.-]+))?
      (?:\+(?<buildmetadata>[0-9A-Za-z.-]+))?
    \z}x
  end

  describe 'basic properties' do
    it 'defines a VERSION constant' do
      expect(CovLoupe.const_defined?(:VERSION)).to be true
    end

    it 'exposes VERSION as a non-empty frozen string' do
      expect(CovLoupe::VERSION).to be_a(String)
      expect(CovLoupe::VERSION).not_to be_empty
      expect(CovLoupe::VERSION).to be_frozen
    end
  end

  describe 'semantic versioning compliance' do
    let(:semver_match) { CovLoupe::VERSION.match(semver_regex) }

    it 'matches the semver pattern (allowing dot or hyphen prerelease)' do
      expect(semver_match).not_to be_nil,
        "VERSION '#{CovLoupe::VERSION}' does not match semantic versioning format"
    end

    it 'has numeric major/minor/patch components' do
      expect(semver_match).not_to be_nil
      %i[major minor patch].each do |part|
        expect(semver_match[part].to_i).to be >= 0
      end
    end

    context 'with prerelease metadata' do
      before { stub_const('CovLoupe::VERSION', '9.9.9-rc.1') }

      it 'captures non-empty prerelease components' do
        prerelease = CovLoupe::VERSION.match(semver_regex)[:prerelease]
        expect(prerelease).not_to be_empty
        expect(prerelease).not_to start_with('.')
        expect(prerelease).not_to end_with('.')
      end
    end

    context 'with build metadata' do
      before { stub_const('CovLoupe::VERSION', '9.9.9+build.42') }

      it 'captures valid build metadata' do
        build_meta = CovLoupe::VERSION.match(semver_regex)[:buildmetadata]
        expect(build_meta).to match(/\A[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*\z/)
      end
    end
  end

  describe 'version consistency' do
    it 'matches the gemspec reference' do
      version_line = File.readlines(gemspec_file).find { |line| line.include?('spec.version') }
      expect(version_line).to include('CovLoupe::VERSION')
    end

    it 'is not the initial placeholder version' do
      expect(CovLoupe::VERSION).not_to eq('0.0.0')
    end
  end

  describe 'runtime dependency constraints' do
    # MCP 0.15 changed argument-validation failures from JSON-RPC errors to
    # tools/call results with isError: true.
    it 'supports MCP 0.15 through 1.x' do
      gemspec = Gem::Specification.load(gemspec_file)
      mcp_dependency = gemspec.runtime_dependencies.find { |dependency| dependency.name == 'mcp' }
      expect(mcp_dependency).not_to be_nil, 'expected the gemspec to declare an mcp runtime dependency'

      requirement = mcp_dependency.requirement
      expect(requirement).to be_satisfied_by(Gem::Version.new('0.15.0'))
      expect(requirement).not_to be_satisfied_by(Gem::Version.new('0.14.0'))
      expect(requirement).to be_satisfied_by(Gem::Version.new('1.0.0'))
      expect(requirement).not_to be_satisfied_by(Gem::Version.new('2.0.0'))
    end
  end

  describe 'standalone version file load' do
    it 'defines the module and VERSION when only version.rb is loaded' do
      original_version = CovLoupe::VERSION

      stub_const('CovLoupe', Module.new do
        class << self
          attr_accessor :default_log_file, :active_log_file
        end
      end)

      load version_file

      expect(Object.const_defined?(:CovLoupe)).to be true
      expect(CovLoupe::VERSION).to eq(original_version)
    end
  end

  describe 'version file guard behavior' do
    it 'defines the version when missing' do
      stub_const('CovLoupe', Module.new do
        class << self
          attr_accessor :default_log_file, :active_log_file
        end
      end)

      load version_file

      expect(CovLoupe::VERSION).to match(semver_regex)
    end

    it 'does not overwrite the version when already defined' do
      stub_const('CovLoupe', Module.new do
        class << self
          attr_accessor :default_log_file, :active_log_file
        end
        const_set(:VERSION, 'custom-version')
      end)

      load version_file

      expect(CovLoupe::VERSION).to eq('custom-version')
    end
  end
end
