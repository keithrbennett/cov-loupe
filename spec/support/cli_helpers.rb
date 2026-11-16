# frozen_string_literal: true

# CLI test helpers
module CLITestHelpers
  # Run the CLI entry point (CovLoupe.execute) and return [stdout, stderr, exit_status].
  def run_cli_with_status(*argv)
    status, out_str, err_str = capture_io { CovLoupe.execute(argv.flatten) }
    [out_str, err_str, status]
  end

  def run_fixture_cli_with_status(*argv)
    run_cli_with_status(*fixture_cli_args(*argv))
  end

  def run_fixture_cli_output(*argv)
    stdout, _stderr, _status = run_fixture_cli_with_status(*argv)
    stdout
  end

  private def fixture_cli_args(*argv)
    args = argv.flatten
    fixture_root = File.dirname(FIXTURE_PROJECT1_COVERAGE_PATH, 2)

    unless args.any? do |arg|
      arg == '--root' || arg.start_with?('--root=') || arg.start_with?('-R')
    end
      args = ['--root', fixture_root] + args
    end

    unless args.any? do |arg|
      arg == '--coverage-file' || arg.start_with?('--coverage-file=') || arg.start_with?('-c')
    end
      args = ['--coverage-file', FIXTURE_PROJECT1_COVERAGE_PATH] + args
    end

    args
  end
end
