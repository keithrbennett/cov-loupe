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

        previous_version = ReleaseMetadata.version_from(version_source)
        version_file.write(updated_version)
        notes_file.write(updated_notes)
        puts "Updated lib/cov_loupe/version.rb and RELEASE_NOTES.md for v#{@version}."
        print_next_steps(previous_version)
      end

      private def print_next_steps(previous_version)
        puts
        puts 'Next steps:'
        puts '  git --no-pager diff lib/cov_loupe/version.rb RELEASE_NOTES.md'
        if major_bump?(previous_version)
          puts "  Major release: add docs/user/migrations/MIGRATING_TO_V#{major(@version)}.md, link it from"
          puts '    the migration indexes, and make sure RELEASE_NOTES.md has a ### Breaking section'
          puts '    (see docs/dev/RELEASING.md, "Major releases")'
        end
        puts '  git add lib/cov_loupe/version.rb RELEASE_NOTES.md  # plus any docs you changed'
        puts "  git commit -m 'Release version #{@version}'"
        puts '  git push origin main'
        puts '  bin/pre-release-check'
      end

      private def major(version) = version.to_s[/\A\d+/].to_i

      # A stable X.0.0 always counts, so finalizing X.0.0.pre.N (same major) still gets the reminder.
      private def major_bump?(previous_version)
        return true if stable_major_release?

        previous_version && major(@version) > major(previous_version)
      end

      private def stable_major_release?
        !Gem::Version.new(@version).prerelease? && @version.match?(/\A\d+\.0\.0\z/)
      end

      private def abort_with(message)
        warn "ERROR: #{message}"
        exit 1
      end
    end
  end
end
