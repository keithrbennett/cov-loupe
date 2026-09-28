# frozen_string_literal: true

require 'pathname'
require_relative 'release_metadata'

module CovLoupe
  module Scripts
    class ReleaseBump
      ROOT = Pathname.new(__dir__).join('../../..').expand_path

      def initialize(version)
        @version = version.to_s
      end

      def call
        abort_with('Provide a version, for example: rake "release:bump[7.1.0]"') if @version.empty?
        abort_with("Invalid release version: #{@version}") unless ReleaseMetadata.valid_version?(@version)

        version_file = ROOT.join('lib/cov_loupe/version.rb')
        notes_file = ROOT.join('RELEASE_NOTES.md')
        version_source = version_file.read
        notes_source = notes_file.read

        abort_with("Could not find exactly one VERSION assignment in #{version_file}") unless
          ReleaseMetadata.version_from(version_source)
        abort_with("Could not find exactly one '## Unreleased' heading in #{notes_file}") unless
          notes_source.scan(ReleaseMetadata::UNRELEASED_HEADING).one?
        abort_with("Release notes already contain a heading for v#{@version}") if
          ReleaseMetadata.release_heading?(notes_source, @version)

        updated_version = ReleaseMetadata.replace_version(version_source, @version)
        updated_notes = notes_source.sub(ReleaseMetadata::UNRELEASED_HEADING) do |heading|
          carriage_return = heading.end_with?("\r") ? "\r" : ''
          newline = "#{carriage_return}\n"
          "## Unreleased#{newline}#{newline}## v#{@version}#{carriage_return}"
        end

        version_file.write(updated_version)
        notes_file.write(updated_notes)
        puts "Updated lib/cov_loupe/version.rb and RELEASE_NOTES.md for v#{@version}."
      end

      private def abort_with(message)
        warn "ERROR: #{message}"
        exit 1
      end
    end
  end
end
