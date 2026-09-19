# Documentation Server

[Back to Developer Documentation](README.md)

This project uses MkDocs to serve the Markdown documentation locally. The repository keeps the Python
documentation dependencies separate from the Ruby gem dependencies in `.docs-venv`.

Run `bin/set-up-python-for-doc-server`, `bin/start-doc-server`, and the `docs:setup` and `docs:serve` Rake
tasks from the repository root; they use `.docs-venv` relative to the current directory. `bin/build-docs`,
`bin/audit-docs-deps`, and `bin/update-docs-deps` resolve the repository paths themselves and work from any
directory. The docs dependency set requires Python 3.10 or newer.

## First-Time Setup

Use the setup script when you want the fastest interactive setup:

```bash
source bin/set-up-python-for-doc-server
```

The script must be sourced because it creates and activates `.docs-venv` in the current shell. It installs the
locked Python packages from `requirements-lock.txt`, including MkDocs and the configured MkDocs plugins. If
your default `python3` is older than 3.10, make `python3` resolve to a newer interpreter before sourcing the
script.

After setup, start the server:

```bash
bin/start-doc-server
```

MkDocs prints the local URL when it starts. By default, the site is served at:

```text
http://127.0.0.1:8000/
```

MkDocs reloads the browser after Markdown changes. Stop it with `Ctrl+C`.

## Later Sessions

If `.docs-venv` already exists, activate it and start the server:

```bash
source .docs-venv/bin/activate
bin/start-doc-server
```

`bin/start-doc-server` also checks `.docs-venv/bin/mkdocs` first, so it can usually find the project-local
MkDocs executable even if the virtual environment is not currently active. It falls back to `mkdocs` on your
`PATH`, and if neither exists it creates `.docs-venv` first.

The helper script does not forward extra flags. To pass MkDocs options, run MkDocs directly, for example
`mkdocs serve --dev-addr 127.0.0.1:8001`.

## Rake Tasks

The same workflow is available through Rake:

```bash
bundle exec rake docs:setup
bundle exec rake docs:serve
```

Use the Rake tasks for non-interactive setup or when you want to stay within the Ruby project tooling. The
`docs:setup` task creates `.docs-venv` and installs `requirements-lock.txt`.

## Dependency Updates and Audits

The documentation tooling is pinned in `requirements-lock.txt`, so it does not pick up security fixes on its
own. Two scripts (each also available as a Rake task) keep it current. Both create a temporary virtual
environment outside the repository, remove it when they finish, and need network access to PyPI:

```bash
bin/audit-docs-deps    # or: rake docs:audit
bin/update-docs-deps   # or: rake docs:update_deps
```

- `bin/audit-docs-deps` checks `requirements-lock.txt` with `pip-audit` and exits non-zero if it finds known
  vulnerabilities.
- `bin/update-docs-deps` reinstalls from the version ranges in `requirements.txt` and rewrites
  `requirements-lock.txt` only if every step succeeds. Afterward, review `git diff requirements-lock.txt`, run
  `bin/build-docs`, and re-run the audit. If an advisory needs a version outside a range in
  `requirements.txt`, widen the range first.

`rake security` runs this audit together with the Ruby audits.

CI runs `bin/audit-docs-deps` in the **Security audit** job, so a newly published advisory against a pinned
package fails that job until `requirements-lock.txt` is updated.

## Strict Build Check

Before publishing or after changing MkDocs navigation, run a strict build:

```bash
bin/build-docs
```

or:

```bash
bundle exec rake docs:build
```

This runs `mkdocs build --strict`, using `.docs-venv` if it exists and otherwise `mkdocs` from your `PATH`
(it creates `.docs-venv` if there is neither), and writes the site to `site/`. The command fails on strict MkDocs errors. Git ignores both
`.docs-venv/` and `site/`.

## Publishing Documentation

The GitHub Actions workflow publishes documentation only for final release tags matching `vX.Y.Z` (for
example `v7.0.0`). Pre-release tags such as `v7.0.0.pre.1` or `v7.0.0-rc1` do not publish documentation.
Pull requests and documentation-related pushes to `main` only build the site for validation. The web
documentation is refreshed when the next final release tag is published.

The workflow publishes with `mkdocs gh-deploy --force`, which pushes the built site to the `gh-pages` branch.
To deploy from a local checkout instead, check out the version tag and run `bundle exec rake docs:deploy`.

Repository settings required for publishing:

- GitHub Pages must be configured to publish from the `gh-pages` branch (**Settings > Pages**).

## Key Files

- `mkdocs.yml` - MkDocs configuration, plugin setup, excluded paths, and site navigation.
- `docs/index.md` - MkDocs landing page.
- `requirements-lock.txt` - Locked Python dependencies used by the setup script and Rake task.
- `requirements.txt` - Broad dependency constraints for documentation tooling.
- `bin/set-up-python-for-doc-server` - First-time interactive environment setup.
- `bin/start-doc-server` - Starts `mkdocs serve` with the project configuration.
- `bin/build-docs` - Runs `mkdocs build --strict` with the project configuration.
- `bin/deploy-docs` - Builds and deploys the documentation with `mkdocs gh-deploy`.
- `bin/audit-docs-deps` - Audits `requirements-lock.txt` for known vulnerabilities with `pip-audit`.
- `bin/update-docs-deps` - Regenerates `requirements-lock.txt` from `requirements.txt`.

## Troubleshooting

If `bin/start-doc-server` reports that `mkdocs` is missing, run this from the repository root:

```bash
source bin/set-up-python-for-doc-server
```

If `python3 -m venv` is unavailable on Ubuntu, install the system venv package for your Python version and run
the setup command again.

If setup reports that Python is too old, install Python 3.10 or newer, make sure `python3` resolves to it, and
run the setup command again.

If port `8000` is already in use, run MkDocs directly with another address:

```bash
mkdocs serve --dev-addr 127.0.0.1:8001
```

If rendered Markdown still looks stale after restarting the server, hard-refresh the browser page. For
example, use `Cmd+Shift+R` on macOS.
