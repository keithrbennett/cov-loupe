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

  it 'prints next-step commands without major-release guidance for a minor bump' do
    _result, out, _err = capture_io { bump.call }

    expect(out).to include('git --no-pager diff', "Release version 7.1.0'", 'bin/pre-release-check')
    expect(out).not_to include('MIGRATING_TO_V')
  end

  it 'points to major-release documentation work when the major version increases' do
    _result, out, _err = capture_io { described_class.new('8.0.0').call }

    expect(out).to include('docs/user/migrations/MIGRATING_TO_V8.md', '### Breaking')
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

  it 'refuses an empty version without changing either file' do
    empty_bump = described_class.new('')
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { empty_bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Provide a version')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'refuses a nil version without changing either file' do
    nil_bump = described_class.new(nil)
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { nil_bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Provide a version')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'refuses a missing VERSION assignment without changing either file' do
    version_file.write("module CovLoupe\nend\n")
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Could not find exactly one VERSION assignment')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'refuses a duplicate VERSION assignment without changing either file' do
    version_file.write("VERSION = '7.0.0'\nVERSION = '7.0.1'\n")
    original_version = version_file.read
    original_notes = notes_file.read

    _result, _out, err = capture_io do
      expect { bump.call }.to raise_error(SystemExit)
    end

    expect(err).to include('Could not find exactly one VERSION assignment')
    expect(version_file.read).to eq(original_version)
    expect(notes_file.read).to eq(original_notes)
  end

  it 'preserves CRLF line endings in both files' do
    version_file.write("module CovLoupe\r\n  VERSION = '7.0.0.pre.1' unless defined?(CovLoupe::VERSION)\r\nend\r\n")
    notes_file.write("# Release Notes\r\n\r\n## Unreleased\r\n\r\n- Changes for the next release\r\n")

    _out, _err = capture_io { bump.call }

    expect(version_file.read).to include("VERSION = '7.1.0' unless defined?(CovLoupe::VERSION)\r\n")
    expect(notes_file.read)
      .to include("## Unreleased\r\n\r\n## v7.1.0\r\n\r\n- Changes for the next release\r\n")
  end
end
