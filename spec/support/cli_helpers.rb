# frozen_string_literal: true

# CLI test helpers
module CLITestHelpers
  # Run CLI with the given arguments and return [stdout, stderr, exit_status]
  def run_cli_with_status(*argv)
    cli = CovLoupe::CoverageCLI.new
    status = nil
    _result, out_str, err_str = capture_io do
      cli.run(argv.flatten)
      status = 0
    rescue SystemExit => e
      status = e.status
    end
    [out_str, err_str, status]
  end

  def run_fixture_cli_with_status(*argv)
    run_cli_with_status(*fixture_cli_args(*argv))
  end

  # Run the full CovLoupe.run entry point (including global ConfigParser)
  def run_full_cli_with_status(*argv)
    status = nil
    _result, out_str, err_str = capture_io do
      CovLoupe.run(argv.flatten)
      status = 0
    rescue SystemExit => e
      status = e.status
    end
    [out_str, err_str, status]
  end

  def run_fixture_full_cli_with_status(*argv)
    run_full_cli_with_status(*fixture_cli_args(*argv))
  end

  def run_fixture_cli_output(*argv)
    stdout, _stderr, _status = run_fixture_cli_with_status(*argv)
    stdout
  end

  private def fixture_cli_args(*argv)
    args = argv.flatten
    fixture_root = File.dirname(FIXTURE_PROJECT1_RESULTSET_PATH, 2)

    unless args.any? do |arg|
      arg == '--root' || arg.start_with?('--root=') || arg.start_with?('-R')
    end
      args = ['--root', fixture_root] + args
    end

    unless args.any? do |arg|
      arg == '--coverage-file' || arg.start_with?('--coverage-file=') || arg.start_with?('-r')
    end
      args = ['--coverage-file', FIXTURE_PROJECT1_RESULTSET_PATH] + args
    end

    args
  end
end
