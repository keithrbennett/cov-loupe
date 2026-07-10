# Contributing to cov-loupe

[Back to main README](docs/index.md)

Thank you for your interest in contributing.

Bug reports, feature proposals, documentation suggestions, and other feedback are welcome.

---

## Before Submitting a Pull Request

Please do not submit a pull request unless you have first opened an issue and received explicit approval from the maintainer to proceed.

Discussing a proposal in an issue does not by itself constitute approval. Please wait until the maintainer specifically confirms that a pull request would be welcome.

This project is maintained by a single developer. Even a well-intentioned and technically sound pull request can require substantial review, testing, discussion, and ongoing maintenance. A proposed change may also conflict with the project's scope, design, priorities, or planned work.

The contribution process is:

1. Open an issue describing the problem or proposed improvement.
2. Discuss the desired behavior and, when useful, the likely implementation.
3. Wait for explicit approval to prepare a pull request.
4. Submit a pull request only after receiving that approval.

Pull requests submitted without prior approval may be closed without detailed review.

### AI-Assisted Contributions

AI-assisted work is welcomed. The same prior-approval requirement applies whether the work is produced manually or with AI assistance.

Contributors are responsible for supervising and validating their work. A pull request should not shift the primary burden of reviewing, debugging, or establishing correctness to the maintainer.

---

## Reporting Issues

Before opening an issue:

- Check whether an existing issue already addresses the subject.
- Include clear reproduction steps when reporting a problem.
- Describe the expected and actual behavior.
- Include your Ruby version (`ruby -v`), operating system, and any other relevant environment information.
- Keep discussion technical and respectful. See the [Code of Conduct](docs/code_of_conduct.md).

---

## Preparing an Approved Change

After receiving explicit approval to submit a pull request:

1. Fork the repository on GitHub.
2. Create a branch for your work:

   ```bash
   git checkout -b feature/my-change
   ```

3. Install dependencies:

   ```bash
   bundle install
   ```

4. Make your changes, following the project's existing coding style.
5. Run the tests:

   ```bash
   bundle exec rspec
   ```

6. Run RuboCop:

   ```bash
   bundle exec rubocop
   ```

7. Commit the changes with a clear, informative message.
8. Push the branch and open a pull request against `main`.

Pull requests should:

- Link to the issue in which the change was approved.
- Include or update tests for new or changed behavior.
- Pass all existing tests and RuboCop checks.
- Update documentation and examples when behavior changes.
- Explain how the change was tested and validated.

---

## Development Setup

This project requires Ruby 3.2 or later because of the `mcp` gem dependency.

A typical setup is:

```bash
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install
bundle exec rspec
```

Useful commands and entry points include:

- `bundle exec rspec` — run the test suite
- `bundle exec rubocop` — run static analysis and style checks
- `bundle exec rake` — run the default Rake tasks
- `exe/cov-loupe` — run the CLI or MCP entry point for end-to-end testing

---

## Documentation

This project uses [MkDocs](https://www.mkdocs.org/) with the [Material theme](https://squidfunk.github.io/mkdocs-material/) to build and serve its documentation.

To run the documentation locally:

```bash
pip3 install -r requirements.txt
mkdocs serve
```

The documentation will be available at <http://127.0.0.1:8000>.

For detailed platform-specific installation instructions and troubleshooting, see [Documentation Development](docs/dev/DEVELOPMENT.md#documentation-development).

---

## Code of Conduct

Please review and follow the [Code of Conduct](docs/code_of_conduct.md).

Instances of unacceptable behavior may be reported through GitHub's [Report Abuse form](https://github.com/contact/report-abuse).