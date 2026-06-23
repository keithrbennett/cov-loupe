# frozen_string_literal: true

# Validation predicate: Total project coverage >= 85%
# Usage: cov-loupe validate examples/success_predicates/project_coverage_minimum_predicate.rb

->(model) { model.project_totals['lines']['percentage'] >= 85.0 }
