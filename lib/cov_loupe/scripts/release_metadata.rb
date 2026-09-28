# frozen_string_literal: true

module CovLoupe
  module Scripts
    module ReleaseMetadata
      VERSION_PATTERN = %r{\A
        (?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)
        (?:[.-](?<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?
        (?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
      \z}x
      VERSION_LINE = /^([ \t]*VERSION[ \t]*=[ \t]*)(['"])([^'"\r\n]+)\2/
      UNRELEASED_HEADING = /^## Unreleased[ \t]*\r?$/

      def self.valid_version?(version)
        match = version.match(VERSION_PATTERN)
        return false unless match

        prerelease_parts = match[:prerelease]&.split('.') || []
        prerelease_parts.none? do |part|
          part.match?(/\A\d+\z/) && part.length > 1 && part.start_with?('0')
        end
      end

      def self.version_from(source)
        matches = source.lines.filter_map { |line| line.match(VERSION_LINE) }
        return matches.first[3] if matches.one?

        nil
      end

      def self.replace_version(source, version)
        source.sub(VERSION_LINE) do
          match = Regexp.last_match
          "#{match[1]}#{match[2]}#{version}#{match[2]}"
        end
      end

      def self.release_heading?(source, version)
        heading = /^## v#{Regexp.escape(version)}(?:[ \t]+.*)?\r?$/
        source.match?(heading)
      end

      def self.unreleased_content?(source)
        lines = source.lines
        heading_index = lines.index { |line| line.match?(UNRELEASED_HEADING) }
        return false unless heading_index

        content = lines[(heading_index + 1)..] || []
        section = content.take_while { |line| !line.match?(/^##(?:[ \t]|$)/) }
        section.any? { |line| !line.strip.empty? }
      end
    end
  end
end
