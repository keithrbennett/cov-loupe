# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'cov_loupe/scripts/release_bump'

RSpec.describe CovLoupe::Scripts::ReleaseBump do
  subject(:bump) { described_class.new(version) }

  let(:version) { '7.1.0' }
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:version_file) { root.join('lib/cov_loupe/version.rb') }
  let(:notes_file) { root.join('RELEASE_NOTES.md') }

  before do
    stub_const('CovLoupe::Scripts::ReleaseBump::ROOT', root)
    FileUtils.mkdir_p(version_file.dirname)
    version_file.write("module CovLoupe\n  VERSION = '7.0.0.pre.1' unless defined?(CovLoupe::VERSION)\nend\n")
    notes_file.write("# Release Notes\n\n## Unreleased\n\n- Changes for the next release\n")
  end

  after { FileUtils.remove_entry(root) }

  it 'updates the version and release notes heading' do
    _out, _err = capture_io { bump.call }

    expect(version_file.read).to include("VERSION = '7.1.0'")
    expect(notes_file.read).to include("## Unreleased\n\n## v7.1.0\n\n- Changes for the next release\n")
  end

  it 'accepts the project prerelease version format' do
    prerelease_bump = described_class.new('7.1.0.pre.1')

    expect { suppress_io { prerelease_bump.call } }.not_to raise_error
    expect(version_file.read).to include("VERSION = '7.1.0.pre.1'")
    expect(notes_file.read).to include("## v7.1.0.pre.1\n")
  end

  it 'rejects an invalid version without changing either file' do
    invalid_bump = described_class.new('7.1.0+build.1')
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { invalid_bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Invalid release version: 7.1.0+build.1')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'rejects missing or duplicate Unreleased headings without editing files' do
    original_version = version_file.read
    notes_file.write("## v7.0.0\n\n## Unreleased\n\n## Unreleased\n")
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include("exactly one '## Unreleased' heading")
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'refuses a version that already has a release heading' do
    notes_file.write("## v7.1.0\n\n- Existing release\n\n## Unreleased\n")
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Release notes already contain a heading for v7.1.0')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end
end
