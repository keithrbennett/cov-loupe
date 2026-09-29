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
end
