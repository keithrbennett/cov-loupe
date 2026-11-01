# Simplify and Document Code Logic

**Purpose:** Identify and improve complex, unclear, or surprising code logic
through simplification or documentation.

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read
   [ai-code-evaluator-guidelines.md](../guidelines/ai-code-evaluator-guidelines.md),
   especially [Method Length and
   Complexity](../guidelines/ai-code-evaluator-guidelines.md#method-length-and-complexity).
   Do not split a long method that is already cohesive and clear.

---

## When to Use This

- Code has complex conditionals (>3 levels of nesting)
- Logic is surprising or differs from standard conventions
- Methods/functions are difficult to understand
- Variable or method names are unclear
- Edge cases lack explanation

## What to Look For

### Complexity Indicators
- **Deep nesting:** Conditionals or loops nested more than 3 levels
- **Long methods:** Methods that require excessive mental effort to understand
- **Unclear variable names:** Names that don't clearly indicate purpose
- **Magic numbers/strings:** Unexplained literal values
- **Complex boolean expressions:** Compound conditions that are hard to parse

### Surprising Behavior
- Logic that differs from typical language/framework conventions
- Non-obvious side effects
- Implicit assumptions about state or input
- Edge case handling that isn't self-evident

### Missing Context
- Unclear intent or purpose
- Inadequate or missing explanatory comments
- Undocumented edge cases
- Assumptions that aren't stated

## Actions to Take

For each instance of complex or unclear logic:

### 1. Assess Simplification Potential
- Can the logic be rewritten more clearly?
- Would extracting helper methods improve clarity?
- Can complex conditions be simplified or inverted?
- Would better variable names help?

### 2. If Simplification is Possible
- Refactor to simpler, more readable code
- Extract helper methods with clear, descriptive names
- Use early returns to reduce nesting
- Break complex expressions into named intermediate variables
- Replace magic values with named constants

### 3. If Simplification is Not Possible
- Add clarifying comments explaining the "why"
- Document edge cases and assumptions
- Add examples in comments if helpful
- Explain why simpler approaches won't work

## Constraints

- **Preserve behavior:** Do not change functionality, output, or public API.
  If you find a bug, report it instead of fixing it here.
- **Test first:** Before refactoring code, check its coverage with cov-loupe;
  add specs for uncovered paths you are about to change.
- **Verify:** Run the relevant specs as you go and the full suite
  (`bundle exec rspec`) at the end.
- **Lint:** Run `bundle exec rubocop` (add `--cache false` if cache writes fail
  in a sandbox) and fix every offense.
- **Comments:** Explain *why*, not *what*; do not comment code that is already
  clear.

## Examples

### Before: Complex nested conditionals
```ruby
def process_order(order)
  if order.valid?
    if order.items.any?
      if order.payment_method
        if order.payment_method.authorized?
          complete_order(order)
        else
          reject_order(order, "Payment not authorized")
        end
      else
        reject_order(order, "No payment method")
      end
    else
      reject_order(order, "No items")
    end
  else
    reject_order(order, "Invalid order")
  end
end
```

### After: Using early returns
```ruby
def process_order(order)
  return reject_order(order, "Invalid order") unless order.valid?
  return reject_order(order, "No items") if order.items.empty?
  return reject_order(order, "No payment method") unless order.payment_method
  unless order.payment_method.authorized?
    return reject_order(order, "Payment not authorized")
  end

  complete_order(order)
end
```

### Before: Unclear logic
```ruby
def calculate_price(item)
  # What is 0.8? Why multiply by it?
  item.base_price * 0.8 if item.category == 3
end
```

### After: Documented with constants
```ruby
# Discount rate for clearance items (20% off)
CLEARANCE_DISCOUNT = 0.8
CLEARANCE_CATEGORY = 3

def calculate_price(item)
  return item.base_price unless item.category == CLEARANCE_CATEGORY

  item.base_price * CLEARANCE_DISCOUNT
end
```

## Output

Make changes directly to the code files, then summarize each change in one
line (`path:line` and what was simplified or documented).

Do not run `git commit`. Stage only the files you changed and propose a concise
commit message that explains what was simplified or documented and why.
