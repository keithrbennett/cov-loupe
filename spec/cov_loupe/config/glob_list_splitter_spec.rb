# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CovLoupe::GlobListSplitter do
  # Backslash handling differs on Windows; pin the platform so these cases are deterministic.
  before { allow(CovLoupe).to receive(:windows?).and_return(false) }

  # Each case: the raw --tracked-globs value, the patterns it must split into, and paths
  # that File.fnmatch must match with at least one of those patterns. The path check makes
  # each case confirm the split agrees with Ruby's own glob rules, not just with the
  # splitter's reading of them.
  [
    ['a plain comma list', 'lib/**/*.rb,app/**/*.rb', ['lib/**/*.rb', 'app/**/*.rb'],
      %w[lib/a.rb app/b.rb]],
    ['a brace alternative', 'app/{models,controllers}/**/*.rb', ['app/{models,controllers}/**/*.rb'],
      %w[app/models/a.rb app/controllers/b.rb]],
    ['several brace groups in a list', '{lib,app}/**/*.{rb,rake},spec/**/*.rb',
      ['{lib,app}/**/*.{rb,rake}', 'spec/**/*.rb'], %w[app/t.rake spec/x.rb]],
    ['nested braces', '{a,{b,c}}/*.rb,d/*.rb', ['{a,{b,c}}/*.rb', 'd/*.rb'], %w[c/x.rb d/y.rb]],
    ['a comma in a character class', 'x[,;]y.rb,z.rb', ['x[,;]y.rb', 'z.rb'], %w[x,y.rb z.rb]],
    ['brackets inside braces', '{a,[b,c]}.rb', ['{a,[b,c]}.rb'], %w[a.rb]],
    ['an unclosed class inside braces', '{a[,b}', ['{a[,b}'], %w[b]],
    # Ruby expands braces before reading classes, so this is the brace group '{a],b}'.
    ['a brace group crossing a class', 'x[{a],b}c,d', ['x[{a],b}c', 'd'], %w[xac d]],
    ['an escaped comma', 'a\,b.rb,c.rb', ['a\,b.rb', 'c.rb'], %w[a,b.rb c.rb]],
    ['an escaped brace', 'a\{b,c.rb', ['a\{b', 'c.rb'], %w[a{b c.rb]],
    # The spelling the unclosed-'[' error message suggests.
    ['a literal bracket written as [[]', 'a[[]b,c', ['a[[]b', 'c'], ['a[b', 'c']],
    ['a stray closing brace', 'a}b,c', ['a}b', 'c'], %w[a}b c]],
    ['empty items', 'a,,b,', %w[a b], %w[a b]],
    ['an empty value', '', [], []],
  ].each do |desc, value, expected, paths|
    it "splits #{desc}" do
      patterns = described_class.split(value)

      expect(patterns).to eq(expected)
      # On real Windows, cov-loupe turns backslashes into '/' before matching, so the
      # fnmatch check of a backslash escape says nothing about cov-loupe's behavior there.
      next if Gem.win_platform? && value.include?('\\')

      flags = CovLoupe::GlobUtils::GLOB_MATCH_FLAGS
      paths.each do |path|
        expect(patterns.any? { |pattern| File.fnmatch?(pattern, path, flags) })
          .to be(true), "expected #{path} to match one of #{patterns}"
      end
    end
  end

  # Values without '{', '[' or a backslash are what worked before this splitter existed.
  # They must split exactly as OptionParser's Array type did (split on every comma, empty
  # items dropped), so no existing command changes behavior.
  ['lib/**/*.rb', 'lib/**/*.rb,app/**/*.rb', 'a,,b', ',a,', 'lib/*.rb, app/*.rb'].each do |value|
    it "matches a plain comma split for #{value.inspect}" do
      expect(described_class.split(value)).to eq(value.split(',').reject(&:empty?))
    end
  end

  # The third case has a '{' inside a class: Ruby still reads it as an unmatched brace. The
  # last has both unclosed; the brace is reported. The message ends with how to write the
  # bracket literally.
  [
    ['lib/{a,b/*.rb', '{'], ['lib/[ab,c.rb', '['], ['lib/[a{b]*.rb', '{'], ['lib/[a,{b', '{']
  ].each do |value, bracket|
    it "raises UsageError for the unclosed '#{bracket}' in #{value.inspect}" do
      hint = bracket == '[' ? "write '[[]'" : "write '\\{', quoted so the shell keeps the backslash"
      expect { described_class.split(value) }.to raise_error(
        CovLoupe::UsageError,
        "Unclosed '#{bracket}' in --tracked-globs value: #{value.inspect}. " \
          "To match a literal '#{bracket}', #{hint}"
      )
    end
  end

  # A literal '{' cannot be written on Windows, so that message has no hint; '[[]' still works.
  [['lib/{a', ''], ['lib/[a', ". To match a literal '[', write '[[]'"]].each do |value, hint|
    it "on Windows, ends the message for #{value.inspect} with #{hint.inspect}" do
      allow(CovLoupe).to receive(:windows?).and_return(true)

      expect { described_class.split(value) }.to raise_error(
        CovLoupe::UsageError, /: #{Regexp.escape(value.inspect)}#{Regexp.escape(hint)}\z/
      )
    end
  end

  # On Windows a backslash is a path separator, so it must not escape the brace after it.
  it 'treats a backslash as a path separator on Windows' do
    allow(CovLoupe).to receive(:windows?).and_return(true)

    expect(described_class.split('app\{models,controllers}\*.rb,lib\*.rb'))
      .to eq(['app\{models,controllers}\*.rb', 'lib\*.rb'])
  end
end
