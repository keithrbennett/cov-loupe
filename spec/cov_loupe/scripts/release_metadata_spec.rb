# frozen_string_literal: true

require 'spec_helper'
require 'cov_loupe/scripts/release_metadata'

RSpec.describe CovLoupe::Scripts::ReleaseMetadata do
  describe '.valid_version?' do
    # 07.1.0, 7.1.0.rc.01, and 7.1.0.RC1 are unusual but RubyGems::Version#to_s preserves them
    # verbatim, so they pose no risk of the built gem's filename diverging from VERSION.
    %w[7.1.0 0.0.1 10.20.30 7.1.0.pre.1 7.1.0.rc.1 7.1.0.beta 07.1.0 7.1.0.rc.01 7.1.0.RC1]
      .each do |version|
        it "accepts #{version}" do
          expect(described_class.valid_version?(version)).to be(true)
        end
      end

    {
      '7.1.0+build.1' => 'build metadata (rejected by RubyGems)',
      '7.1.0-rc.1'    => 'hyphen prerelease (RubyGems renames it to 7.1.0.pre.rc.1)',
      '7.1.0.pre-1'   => 'hyphen inside a prerelease segment (RubyGems renames it)',
      '7.1'           => 'fewer than three segments',
      '7.1.0.'        => 'trailing dot',
      'v7.1.0'        => 'leading v',
      ''              => 'empty string',
      nil             => 'nil',
      7.1             => 'non-string',
    }.each do |version, reason|
      it "rejects #{version.inspect} (#{reason})" do
        expect(described_class.valid_version?(version)).to be(false)
      end
    end
  end

  describe '.version_from' do
    it 'returns the version from a single VERSION assignment' do
      source = "module CovLoupe\n  VERSION = '7.1.0'\nend\n"
      expect(described_class.version_from(source)).to eq('7.1.0')
    end

    it 'returns nil when there is no VERSION assignment' do
      expect(described_class.version_from("module CovLoupe\nend\n")).to be_nil
    end

    it 'returns nil when there are multiple VERSION assignments' do
      source = "VERSION = '7.1.0'\nVERSION = '7.2.0'\n"
      expect(described_class.version_from(source)).to be_nil
    end

    it 'matches a VERSION assignment with a trailing guard clause' do
      source = "  VERSION = '7.1.0' unless defined?(CovLoupe::VERSION)\n"
      expect(described_class.version_from(source)).to eq('7.1.0')
    end
  end

  describe '.replace_version' do
    it 'replaces the version while preserving surrounding formatting and quote style' do
      source = "module CovLoupe\n  VERSION = '7.0.0' unless defined?(CovLoupe::VERSION)\nend\n"
      updated = described_class.replace_version(source, '7.1.0')
      expect(updated).to eq("module CovLoupe\n  VERSION = '7.1.0' unless defined?(CovLoupe::VERSION)\nend\n")
    end

    it 'preserves double-quote style' do
      source = 'VERSION = "7.0.0"'
      expect(described_class.replace_version(source, '7.1.0')).to eq('VERSION = "7.1.0"')
    end

    it 'returns the source unchanged when there is no VERSION assignment' do
      source = "module CovLoupe\nend\n"
      expect(described_class.replace_version(source, '7.1.0')).to eq(source)
    end
  end

  describe '.release_heading?' do
    it 'matches a bare heading for the version' do
      expect(described_class.release_heading?("## v7.1.0\n", '7.1.0')).to be(true)
    end

    it 'matches a heading with a trailing annotation' do
      expect(described_class.release_heading?("## v7.1.0 (Breaking)\n", '7.1.0')).to be(true)
    end

    it 'matches a heading with trailing CRLF' do
      expect(described_class.release_heading?("## v7.1.0\r\n", '7.1.0')).to be(true)
    end

    it 'does not match a different version' do
      expect(described_class.release_heading?("## v7.2.0\n", '7.1.0')).to be(false)
    end

    it 'does not match a heading where the version is a prefix of a longer token' do
      expect(described_class.release_heading?("## v7.1.0.pre.1\n", '7.1.0')).to be(false)
    end

    it 'does not match when there is no heading at all' do
      expect(described_class.release_heading?("# Release Notes\n", '7.1.0')).to be(false)
    end
  end

  describe '.unreleased_content?' do
    it 'returns false when there is no Unreleased heading' do
      expect(described_class.unreleased_content?("# Release Notes\n\n## v7.1.0\n")).to be(false)
    end

    it 'returns false when the Unreleased section is empty' do
      source = "## Unreleased\n\n## v7.0.0\n\n- Old change\n"
      expect(described_class.unreleased_content?(source)).to be(false)
    end

    it 'returns false when the Unreleased section has only blank lines' do
      source = "## Unreleased\n\n\n## v7.0.0\n"
      expect(described_class.unreleased_content?(source)).to be(false)
    end

    it 'returns true when the Unreleased section has content' do
      source = "## Unreleased\n\n- Pending change\n\n## v7.0.0\n"
      expect(described_class.unreleased_content?(source)).to be(true)
    end

    it 'returns true when the Unreleased section is the last section in the file' do
      source = "## v7.0.0\n\n- Old change\n\n## Unreleased\n\n- Pending change\n"
      expect(described_class.unreleased_content?(source)).to be(true)
    end
  end
end
