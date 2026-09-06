# frozen_string_literal: true

require 'spec_helper'

# The `resultset` terminology predates coverage.json support. Every old name
# still works and warns; these specs pin both halves so the aliases cannot
# rot before they are removed in v7.0.0.
RSpec.describe 'deprecated resultset names' do
  let(:root) { (FIXTURES_DIR / 'project1').to_s }
  let(:resultset) { FIXTURE_PROJECT1_RESULTSET_PATH }

  around do |example|
    CovLoupe::Deprecation.reset!
    CovLoupe::Deprecation.enabled = true
    example.run
    CovLoupe::Deprecation.reset!
    CovLoupe::Deprecation.enabled = false
  end

  describe 'constants' do
    it 'resolves ResultsetNotFoundError to CoverageFileNotFoundError' do
      expect(CovLoupe::ResultsetNotFoundError).to be(CovLoupe::CoverageFileNotFoundError)
    end

    it 'resolves ResultsetPathResolver to CoverageFilePathResolver' do
      expect(CovLoupe::Resolvers::ResultsetPathResolver)
        .to be(CovLoupe::Resolvers::CoverageFilePathResolver)
    end
  end

  describe 'CoverageModel' do
    it 'accepts resultset: as coverage_file: and warns' do
      model = nil
      expect { model = CovLoupe::CoverageModel.new(root: root, resultset: resultset) }
        .to output(/CoverageModel.new\(resultset:\) is deprecated/).to_stderr
      expect(model.coverage_file_path).to eq(resultset)
    end

    it 'prefers an explicit coverage_file: over resultset:' do
      model = suppress_io do
        CovLoupe::CoverageModel.new(root: root, coverage_file: resultset,
          resultset: '/nonexistent/.resultset.json')
      end
      expect(model.coverage_file_path).to eq(resultset)
    end

    it 'answers #resultset_path with the coverage file path and warns' do
      model = CovLoupe::CoverageModel.new(root: root, coverage_file: resultset)

      expect { expect(model.resultset_path).to eq(resultset) }
        .to output(/CoverageModel#resultset_path is deprecated/).to_stderr
    end
  end

  describe 'CoverageRepository' do
    it 'answers #resultset_path with the coverage file path and warns' do
      repo = CovLoupe::Repositories::CoverageRepository.new(root: root)

      expect { expect(repo.resultset_path).to eq(repo.coverage_file_path) }
        .to output(/CoverageRepository#resultset_path is deprecated/).to_stderr
    end
  end

  describe 'ResolverHelpers' do
    it 'resolves through .find_resultset and warns' do
      found = nil
      expect { found = CovLoupe::Resolvers::ResolverHelpers.find_resultset(root) }
        .to output(/ResolverHelpers.find_resultset is deprecated/).to_stderr
      expect(found).to eq(CovLoupe::Resolvers::ResolverHelpers.find_coverage_file(root))
    end

    it 'builds a resolver through .create_resultset_resolver and warns' do
      resolver = nil
      expect { resolver = CovLoupe::Resolvers::ResolverHelpers.create_resultset_resolver(root: root) }
        .to output(/ResolverHelpers.create_resultset_resolver is deprecated/).to_stderr
      expect(resolver).to be_a(CovLoupe::Resolvers::CoverageFilePathResolver)
    end
  end

  describe 'CoverageFilePathResolver' do
    it 'resolves through #find_resultset and warns' do
      resolver = CovLoupe::Resolvers::CoverageFilePathResolver.new(root: root)
      found = nil

      expect { found = resolver.find_resultset(resultset: resultset) }
        .to output(/CoverageFilePathResolver#find_resultset is deprecated/).to_stderr
      expect(found).to eq(resultset)
    end
  end

  describe 'AppConfig' do
    it 'reads and writes coverage_file through #resultset and warns' do
      config = CovLoupe::AppConfig.new

      expect { config.resultset = '/tmp/coverage.json' }
        .to output(/AppConfig#resultset= is deprecated/).to_stderr
      expect(config.coverage_file).to eq('/tmp/coverage.json')

      expect { expect(config.resultset).to eq('/tmp/coverage.json') }
        .to output(/AppConfig#resultset is deprecated/).to_stderr
    end
  end

  describe 'stale errors' do
    it 'answers #resultset_path with the coverage file path and warns' do
      error = CovLoupe::CoverageDataStaleError.new(nil, nil, coverage_file_path: resultset)

      expect { expect(error.resultset_path).to eq(resultset) }
        .to output(/CoverageDataStaleError#resultset_path is deprecated/).to_stderr
    end

    it 'answers project-level #resultset_path and warns' do
      error = CovLoupe::CoverageDataProjectStaleError.new(nil, nil, coverage_file_path: resultset)

      expect { expect(error.resultset_path).to eq(resultset) }
        .to output(/CoverageDataProjectStaleError#resultset_path is deprecated/).to_stderr
    end
  end

  describe 'CLI --resultset' do
    it 'sets coverage_file and warns' do
      cli = CovLoupe::CoverageCLI.new

      stderr = capture_stderr { cli.send(:run, ['--resultset', resultset, '--help']) }

      expect(stderr).to include('--resultset is deprecated')
      expect(cli.config.coverage_file).to eq(resultset)
    end
  end

  describe 'MCP resultset argument' do
    it 'is folded into coverage_file and warns' do
      context = CovLoupe::AppContext.new(
        error_handler: CovLoupe::ErrorHandler.new, log_target: File::NULL, mode: :mcp
      )
      config = nil

      expect do
        config = CovLoupe::BaseTool.model_config_for(server_context: context, resultset: resultset)
      end.to output(/the resultset tool argument is deprecated/).to_stderr

      expect(config).to include(coverage_file: resultset)
      expect(config).not_to have_key(:resultset)
    end

    it 'keeps an explicit coverage_file when a client sends both' do
      context = CovLoupe::AppContext.new(
        error_handler: CovLoupe::ErrorHandler.new, log_target: File::NULL, mode: :mcp
      )

      config = suppress_io do
        CovLoupe::BaseTool.model_config_for(
          server_context: context, coverage_file: resultset, resultset: '/nonexistent/x.json'
        )
      end

      expect(config).to include(coverage_file: resultset)
    end
  end
end
