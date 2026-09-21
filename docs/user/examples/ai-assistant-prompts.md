# AI Assistant Prompts

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

A coverage table tells you *which* lines ran. An assistant connected through the MCP server can combine that with the source code, the tests, and the git history to tell you what the gaps *mean*: what behavior is untested, who would notice if it broke, and where a healthy-looking percentage is misleading. The prompts below are written for that. For plain tables and counts, the [CLI examples](cli-examples.md) are enough. For a long, paste-in prompt that produces a complete written report, see the [Prompt Library](../prompts/README.md).

The prompts use paths from the demo project (`lib/payments/`, `app/controllers/`); substitute your own.

## Before You Start

**Run the full test suite first.** cov-loupe's staleness checks compare the coverage file with your source files, so they can't tell that a *partial* run (for example, one spec file) produced it. A partial run makes most of your code look untested, and the analysis will be confidently wrong. If you regenerate coverage during a session, use the full suite: running a subset of specs overwrites `coverage.json` with the subset's numbers.

## Explain What Is Not Tested

"Using the cov-loupe MCP server, look at the uncovered lines in lib/payments/refund_service.rb. Read the surrounding source and explain in plain English which behaviors are not exercised by any test, and what a user would experience if each of those paths were broken. Reference line numbers only to anchor your explanation. Also flag any uncovered code that looks unreachable or unused."

**What you get that the numbers don't give you:** a list of *behaviors* ("a refund for a non-positive amount is never rejected") in place of line numbers, each with its user-visible consequence, plus code that should be deleted rather than tested. Because the assistant reads the code around each gap, it can also notice code that is wrong today. In one real session against cov-loupe's own error handler, it reported:

> No test ever reaches the branch that makes a "missing method 'x' on object" message readable. This one is probably already broken. The regex expects the old message format with a backtick (``undefined method `foo' for …``). Ruby 3.4 and later print ``undefined method 'foo' for an instance of Foo``, … The pattern would then never match, and users would get the raw Ruby message instead of the tidy one.

That was correct, and it is the kind of finding a percentage can never give you.

## Rank by Risk, Not Percentage

"Using the cov-loupe MCP server, look at the coverage gaps across the entire code base and rank the 10 files that pose the most risk. Weigh what the code does (moving money, parsing input, handling errors, producing output users depend on), how recently and how often it changed (git log), how many other files depend on it, and how important the uncovered lines are within it. A well-covered file whose few missing lines are critical can outrank a poorly covered file of low-stakes code. For each file, explain briefly the main risks, and offer high level recommendations on remediation strategies."

**What you get:** an order of work that reflects consequences. A 93% file whose few untested lines decide which record gets returned can outrank a 0% dev-tooling script, and each file comes with a suggested way to fix it.

## Assess Test Quality

"Using the cov-loupe MCP server, analyze the tests across the entire code base for quality: do they detect real failure risks correctly and sufficiently? Give a judgment on test quality for each area of the code base, and explain how well the coverage numbers correlate with actual test quality in each area."

**What you get:** a verdict per area, and where coverage and quality diverge. Run on a project at 100% line coverage, the assistant mutation-tested a temporary copy of the code (16 of 72 injected bugs survived on fully covered lines) and rated calculation and error-handling tests strong, but rendering and CLI tests weak, because their assertions only check that some text appeared. It also found an untested boundary (`>` versus `>=` on a timestamp comparison) and dead code that counted as covered. Expect several minutes on a large project.

## Review Changes

"Using the cov-loupe MCP server, look at what changed on this branch compared with main (git diff main...HEAD). Which changed lines are not covered by any test? For each one, explain what behavior changed and what would go wrong for a user if that change were broken and nobody noticed."

**What you get:** an answer about *your change*, not the whole project. It will also point out changes coverage can't see at all (a `Rakefile`, CI workflows, shell scripts), which is often where a quiet break goes unnoticed, and it can tell you whether a covered line is protected by an assertion or merely executed. Run the full suite on the branch first so the coverage data reflects it.

## Find Patterns

"Using the cov-loupe MCP server, look across all the uncovered lines in lib/ and identify 3 to 5 recurring themes in what is not being tested (for example, a particular kind of error handling or a particular kind of input). For each theme, name the representative files, explain what the pattern says about how the test suite was written, and suggest one test approach that would close the whole theme at once."

**What you get:** a handful of causes instead of a hundred symptoms. Typical themes are "defensive `rescue` branches that need fault injection", "an exception-to-error translation table that needs one data-driven spec", and "public methods nothing calls", where the right fix is to delete code. Each theme comes with a way to close many gaps with one test.

## Turn Gaps into Tests

"Using the cov-loupe MCP server, take the uncovered lines in lib/payments/refund_service.rb. Write specs under spec/ that cover them and run them. Then run the full test suite to refresh coverage.json and confirm, using cov-loupe, that those lines are now covered. Do not change anything under lib/. If a test you write shows the code misbehaving, do not work around it: report it as a bug with the failing example."

**What you get:** tests grounded in the analysis above, checked against real coverage data, and a clear separation between "untested" and "broken". In a real session this produced a table-driven spec that took a file from 74% to 100%, and it also produced a failing example that proved a bug (the Ruby 3.4 message format above) instead of a test bent to pass.
