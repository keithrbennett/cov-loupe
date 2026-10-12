# frozen_string_literal: true

# Validation predicate: Total project coverage >= 85%
# Usage: cov-loupe validate examples/success_predicates/project_coverage_minimum_predicate.rb
# percentage is nil when no lines can be measured (no coverable lines, or all files stale);
# `to_f` turns that into 0.0 so the check fails rather than passing vacuously.

->(model) { model.project_totals['lines']['percentage'].to_f >= 85.0 }
