# frozen_string_literal: true

module CovLoupe
  module Scripts
    module ReleaseMetadata
      # Shape check: at least MAJOR.MINOR.PATCH, dot-separated. Gem::Version does the rest.
      VERSION_PATTERN = /\A\d+\.\d+\.\d+(?:\.[0-9A-Za-z]+)*\z/
      VERSION_LINE = /^([ \t]*VERSION[ \t]*=[ \t]*)(['"])([^'"\r\n]+)\2/
      UNRELEASED_HEADING = /^## Unreleased[ \t]*\r?$/

      # A version is valid only if RubyGems accepts it AND Gem::Version#to_s reproduces it
      # verbatim. #to_s is what `gem build` uses for the built gem's filename, so this is the
      # precise test for "will the artifact filename match our VERSION string and release tag".
      # It rejects forms RubyGems accepts but rewrites, e.g. "7.1.0-rc.1" becomes
      # "7.1.0.pre.rc.1", and rejects build metadata ("+build.1") outright via
      # Gem::Version.correct?. It does NOT reject other RubyGems-legal oddities that #to_s
      # happens to preserve verbatim, such as a leading zero ("07.1.0") or an upper-case
      # prerelease token ("7.1.0.RC1") — those are unusual but pose no filename-mismatch risk.
      def self.valid_version?(version)
        return false unless version.is_a?(String)
        return false unless version.match?(VERSION_PATTERN) && Gem::Version.correct?(version)

        Gem::Version.new(version).to_s == version
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
