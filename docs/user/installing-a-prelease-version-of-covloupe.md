# Installing a Prerelease Version of cov-loupe

[Back to main README](../index.md)

Prerelease versions of gems (those containing `.pre`, `.alpha`, `.beta`, `.rc`, etc.) are **not** installed by default in RubyGems.

## Command Line Installation

When users run `gem install cov-loupe`, RubyGems installs the latest **stable** version, skipping any prereleases.

To install a prerelease, you must explicitly opt in:

```sh
# Install the latest prerelease
gem install cov-loupe --pre

# Install a specific prerelease version
gem install cov-loupe -v 4.0.0.pre
```

## Gemfile

In a Gemfile, you need to explicitly specify the prerelease version:

```ruby
# Exact version
gem 'cov-loupe', '4.0.0.pre'

# Or allow any 4.0.0 prerelease
gem 'cov-loupe', '~> 4.0.0.pre'
```

Without an explicit version constraint that includes the prerelease suffix, Bundler will skip prereleases just like `gem install` does.

## Gemspec Dependencies

For gemspec dependencies on prerelease gems, you must specify the prerelease version explicitly:

```ruby
spec.add_dependency 'cov-loupe', '~> 4.0.0.pre'
```

## Key Point

Version constraints like `~> 4.0` or `>= 4.0` will **not** match prereleases. You must include the prerelease segment in the constraint for it to match.
