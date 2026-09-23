# Dependency Locking and Vulnerability Alert Coverage

[Back to main README](../../index.md)

This document covers whether `Gemfile.lock` is committed, and how that choice interacts with GitHub Dependabot alert coverage.

## Gemfile.lock: Not Committed

### Status

**Accepted** (`28e2cff`) — reaffirmed 2026-09-23 after considering whether it should change to close a Dependabot coverage gap.

### Context

`b7cdc68834c8` committed `Gemfile.lock`, resolved on Ruby 4.0, to pin dependency versions and add the simplecov range-compat CI job. It backfired: the CI matrix (`.github/workflows/test.yml`) runs Ruby 3.2 through 4.0 plus JRuby, and a single lock resolved on one Ruby couldn't serve all of them —

- `parallel 2.2.0` (a transitive dep) requires Ruby >= 3.3, breaking the Ruby 3.2 job.
- JRuby needs C-extension gems replaced with `java`-platform variants, which a CRuby-resolved lock doesn't carry without ongoing hand-maintenance (`bundle lock --add-platform ...`, re-run every time a locked gem changes).

`28e2cff` untracked the lock so each matrix cell resolves independently via `bundle install` (`ruby/setup-ruby`'s `bundler-cache: true`), keeping the simplecov compat job and its `SIMPLECOV_VERSION` pin.

This was revisited after enabling Dependabot alerts (2026-09-23): GitHub's dependency graph, without a committed lockfile, falls back to parsing `Gemfile`/`cov-loupe.gemspec` directly. Confirmed via `gh api repos/keithrbennett/cov-loupe/dependency-graph/sbom` — it sees exactly the 12 gems declared by name in `Gemfile`/gemspec, each as a version *range* (e.g. `rubocop ~> 1.88.0`), with **no transitive dependencies at all**. Recommitting the lock would give Dependabot the full resolved tree, which raised the question of reversing `28e2cff`.

### Decision

Keep `Gemfile.lock` untracked. The CI-matrix breakage that caused `28e2cff` is unrelated to Dependabot and still fully applies; reintroducing it to close a comparatively narrow alerting gap is a bad trade.

The gap is narrower than "no transitive-dependency vulnerability detection": `.github/workflows/test.yml`'s `security` job already runs `bundle exec bundle audit check --update` on every push/PR, against a `Gemfile.lock` resolved fresh in that job (Ruby 4.0.6). That check covers the full transitive tree, including everything Dependabot's dependency graph currently can't see. What it doesn't do is watch continuously — a CVE published against unchanged code isn't caught until the next push triggers CI, whereas Dependabot alerts re-evaluate the graph as new advisories are published, independent of pushes.

### Consequences

- Dependabot alerts cover only the 12 gems named directly in `Gemfile`/`cov-loupe.gemspec`, matched against declared version ranges rather than exact resolved versions. Transitive dependencies of those gems (mostly dev tooling — rubocop, rspec, etc.) generate no Dependabot alert.
- `bundle-audit` (`security` CI job) catches transitive-dependency vulnerabilities today, but only at push/PR time, not continuously between pushes.
- The CI matrix (Ruby 3.2–4.0 + JRuby, Linux/macOS/Windows) keeps resolving independently per job, avoiding the version/platform conflicts `28e2cff` fixed.
- `.github/dependabot.yml`'s `bundler` entry drives scheduled version-update PRs; confirmed (via a second SBOM pull after it was already in place) that this does *not* feed transitive dependencies into the alert graph — version updates and the dependency graph are separate GitHub features.
- If continuous transitive-dependency coverage is wanted later, the correct mechanism is the [Dependency Submission API](https://docs.github.com/en/rest/dependency-graph/dependency-submission) — a CI step that resolves a snapshot and submits it directly, without committing the lock. No ready-made Ruby/Bundler action exists for this today (unlike Maven/Gradle/sbt), so it would be a custom implementation, scoped separately rather than folded into this decision.

### References

- Commits: `b7cdc68` (Track Gemfile.lock; add simplecov range-compat CI job), `28e2cff` (Stop tracking Gemfile.lock; run JRuby CI on Java 21)
- CI matrix: `.github/workflows/test.yml` (`test`, `compat`, `security` jobs)
- Dependency declarations: `cov-loupe.gemspec` (`spec.add_dependency`), `Gemfile` (dev dependencies)
- `.gitignore` (`/Gemfile.lock`)
- Version-update config: `.github/dependabot.yml`
- Transitive vulnerability scanning today: `bundle exec bundle audit check --update` in `.github/workflows/test.yml`'s `security` job
