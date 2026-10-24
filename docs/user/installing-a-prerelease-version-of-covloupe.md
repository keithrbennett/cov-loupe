# Installing a Prerelease Version of cov-loupe

[Back to main README](../../README.md)

Prerelease versions of gems (those containing `.pre`, `.alpha`, `.beta`, `.rc`, etc.) are **not** installed by default in RubyGems.

## Command Line Installation

When users run `gem install cov-loupe`, RubyGems installs the latest **stable** version, skipping any prereleases.

To install a prerelease, you must explicitly opt in:

```sh
# Install the newest version, prereleases included (a newer stable release wins)
gem install cov-loupe --pre

# Install a specific prerelease version
gem install cov-loupe -v 7.0.0.pre.1
```

## Gemfile

In a Gemfile, you need to explicitly specify the prerelease version:

```ruby
# Exact version
gem 'cov-loupe', '7.0.0.pre.1'

# Or allow this prerelease or any later 7.0.x version, including stable releases
gem 'cov-loupe', '~> 7.0.0.pre.1'
```

Without an explicit version constraint that includes the prerelease suffix, Bundler will skip prereleases just like `gem install` does.

## Gemspec Dependencies

For gemspec dependencies on prerelease gems, you must specify the prerelease version explicitly:

```ruby
spec.add_dependency 'cov-loupe', '~> 7.0.0.pre.1'
```

## Key Point

Version constraints like `~> 7.0` or `>= 7.0` will **not** match `7.0.0.pre.1`, because a prerelease sorts below its release (`7.0.0.pre.1 < 7.0`). Include the prerelease segment in the constraint, as above, for it to match.
