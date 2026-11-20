# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'rbconfig'
require 'rubygems/package'
require 'tmpdir'
require_relative 'command_execution'
require_relative 'release_metadata'

module CovLoupe
  module Scripts
    # Installs a built gem into a temporary gem directory and runs the installed executable, to
    # catch packaging mistakes (such as a file or dependency missing from the gemspec) before
    # `gem push`. The directory holds only the gem and copies of the installed gems its
    # declared runtime dependencies resolve to, and GEM_PATH is limited to it. So an undeclared
    # dependency is not found, unless a declared one also depends on it or it is a default gem
    # (such as json), which Ruby always provides. Nothing outside the directory is changed.
    #
    # @api private
    class ReleaseSmokeTest
      include CommandExecution

      ROOT = Pathname.new(__dir__).join('../../..').expand_path
      MCP_HELP_REQUEST = '{"jsonrpc":"2.0","id":1,"method":"tools/call",' \
                         '"params":{"name":"help","arguments":{}}}'
      # The demo project the gem ships, relative to the installed gem.
      DEMO_PROJECT = 'docs/fixtures/demo_project'

      # gem_file defaults to the gem bin/pre-release-check builds for the current version, in
      # the repository root, or else the one rake build writes to pkg/.
      def initialize(gem_file = nil)
        @gem_file = gem_file
      end

      def call
        gem_file = resolve_gem_file
        spec = gem_spec(gem_file)
        version = spec.version.to_s

        Dir.mktmpdir('cov-loupe-smoke') do |gem_home|
          # Resolved, because the installed gem reports paths from __dir__, which resolves
          # symlinks (on macOS the temporary directory is under the symlink /var).
          @gem_home = File.realpath(gem_home)
          @installed_gem = File.join(@gem_home, 'gems', spec.full_name)
          stage_dependencies(spec)
          install(gem_file)
          failures = checks(version).filter_map { |name, check| report(name, check.call) }
          abort_with("#{failures.size} smoke test check(s) failed for #{gem_file.basename}") if failures.any?
          puts "Smoke test passed for #{gem_file.basename}."
        end
      end

      private def resolve_gem_file
        if @gem_file
          path = Pathname.new(@gem_file).expand_path
          abort_with("#{path} does not exist") unless path.exist?
          abort_with("#{path} is not a gem file") unless path.file?
          return path
        end

        version = ReleaseMetadata.version_from(ROOT.join('lib/cov_loupe/version.rb').read) or
          abort_with('Could not read the version from lib/cov_loupe/version.rb')
        name = "cov-loupe-#{version}.gem"
        [ROOT.join(name), ROOT.join('pkg', name)].find(&:file?) or
          abort_with("#{name} not found in the repository root or pkg/; run bin/pre-release-check " \
                     "(or rake build) first, or pass a gem path: rake 'release:smoke_test[path.gem]'")
      end

      # The gem's specification; --version must print the version it declares.
      private def gem_spec(gem_file)
        Gem::Package.new(gem_file.to_s).spec
      rescue Gem::Package::FormatError, Gem::Security::Exception, ArgumentError, Zlib::Error => e
        abort_with("#{gem_file} is not a valid gem: #{e.message}")
      end

      # Copies the installed gems that the gem's declared runtime dependencies resolve to
      # (recursively) into the temporary gem directory: their files, compiled extensions and
      # specification. Copying avoids reinstalling, which would recompile native extensions.
      # Default gems are left out; they load from Ruby's own library directory.
      private def stage_dependencies(spec)
        dependency_closure(spec).each do |dep|
          base = Pathname.new(dep.base_dir)
          [dep.full_gem_path, dep.extension_dir].each do |dir|
            next unless File.directory?(dir)

            target = File.join(@gem_home, Pathname.new(dir).relative_path_from(base))
            FileUtils.mkdir_p(File.dirname(target))
            FileUtils.cp_r(dir, target)
          end
          FileUtils.mkdir_p(File.join(@gem_home, 'specifications'))
          FileUtils.cp(dep.loaded_from, File.join(@gem_home, 'specifications'))
        end
      end

      private def dependency_closure(spec, found = {})
        spec.runtime_dependencies.each do |dependency|
          dep = dependency.to_spec
          next if found.key?(dep.full_name) || dep.default_gem?

          found[dep.full_name] = dep
          dependency_closure(dep, found)
        end
        found.values
      rescue Gem::MissingSpecError => e
        # Also raised (as MissingSpecVersionError) when only other versions are installed.
        abort_with("A runtime dependency is not installed at a version the gem accepts: #{e.message}")
      end

      # Each check returns nil on success, or a failure message.
      private def checks(version)
        {
          '--version prints the version'                 => -> { check_version(version) },
          '--help prints usage'                          => -> { check_help },
          'runs from the installed gem, with its README' => -> { check_installed_copy },
          'totals reads coverage data'                   => -> { check_totals },
          'MCP server answers a help call'               => -> { check_mcp },
        }
      end

      private def check_version(version)
        out, ok = run_installed('--version')
        "expected #{version}, got #{out.inspect}" unless ok && out == version
      end

      private def check_help
        out, ok = run_installed('--help')
        return "--help failed: #{out}" unless ok

        'no usage text' unless out.include?('Usage:')
      end

      # The README path is derived from the installed code's location, so it shows which copy
      # ran; it must also be packaged.
      private def check_installed_copy
        out, ok = run_installed('--path-for', 'docs-local')
        return "--path-for failed: #{out}" unless ok
        unless out.start_with?("#{@gem_home}/")
          return "README path #{out.inspect} is not in the installed gem"
        end

        "README is missing from the gem: #{out}" unless File.file?(out)
      end

      # Uses the demo project's coverage data, which the gem ships.
      private def check_totals
        out, ok = run_installed('totals', '--format', 'json', '--root',
          File.join(@installed_gem, DEMO_PROJECT))
        return "totals failed: #{out}" unless ok

        counts = JSON.parse(out).then { |payload| payload['file_counts'] if payload.is_a?(Hash) }
        return 'totals output has no file_counts' unless counts.is_a?(Hash)

        # Every demo file must be packaged and fresh: a missing file shows as stale (deleted).
        without = counts.dig('without_coverage', 'total').to_i
        return "#{without} demo files have no usable coverage data" if without.positive?

        ok = counts.dig('with_coverage', 'ok')
        "#{ok.inspect} of #{counts['total']} demo files are fresh" unless counts['total'].to_i.positive? &&
          ok == counts['total']
      rescue JSON::ParserError
        "totals output is not JSON: #{out[0, 200].inspect}"
      end

      # Loads the MCP stack, which no other check does, so a missing mcp dependency shows here.
      private def check_mcp
        out, ok = run_installed('-m', 'mcp', stdin_data: "#{MCP_HELP_REQUEST}\n")
        return "MCP server failed: #{out}" unless ok

        response = JSON.parse(out.lines.first.to_s)
        result = response['result'] if response.is_a?(Hash)
        'MCP help call returned no result' unless result.is_a?(Hash) && !result['isError']
      rescue JSON::ParserError
        "MCP output is not JSON-RPC: #{out[0, 200].inspect}"
      end

      private def report(name, failure)
        puts failure ? "✗ #{name}: #{failure}" : "✓ #{name}"
        failure
      end

      private def install(gem_file)
        gem_command = File.join(RbConfig::CONFIG['bindir'], Gem.win_platform? ? 'gem.cmd' : 'gem')
        # --local: no network access. --install-dir: a gemrc setting such as --user-install cannot
        # send it elsewhere. --ignore-dependencies: with --install-dir, RubyGems does not resolve
        # them to the staged copies; running the gem activates them, and fails if one is missing.
        out, ok = run_isolated(gem_command, 'install', '--local', '--no-document', '--ignore-dependencies',
          '--install-dir', @gem_home, gem_file.to_s)
        abort_with("Could not install #{gem_file.basename} into #{@gem_home}:\n#{out}") unless ok
        abort_with("#{gem_file.basename} was not installed in #{@installed_gem}") unless
          File.directory?(@installed_gem)
        puts "✓ Installed #{gem_file.basename} into #{@gem_home}"
      end

      # Runs the installed executable from the temporary directory, so this checkout's files
      # are not picked up.
      private def run_installed(*, stdin_data: '')
        run_isolated(RbConfig.ruby, File.join(@gem_home, 'bin', 'cov-loupe'), *, stdin_data: stdin_data)
      end

      # Runs a command with only the temporary gem directory as its gems, and no Bundler
      # environment (rake may run under bundle exec). Returns its
      # output (stdout, or stdout and stderr on failure) and whether it succeeded.
      private def run_isolated(*cmd, stdin_data: '')
        stdout, stderr, status = without_bundler do
          Open3.capture3(isolated_env, *cmd, chdir: @gem_home, stdin_data: stdin_data)
        end
        [status.success? ? stdout.strip : "#{stdout}#{stderr}".strip, status.success?]
      rescue SystemCallError => e
        ["could not run #{cmd.first}: #{e.message}", false]
      end

      private def isolated_env
        {
          'GEM_HOME'       => @gem_home,
          'GEM_PATH'       => @gem_home,
          'COV_LOUPE_OPTS' => nil,
        }
      end

      private def without_bundler(&)
        defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
      end
    end
  end
end
