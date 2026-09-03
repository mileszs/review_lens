# Contributing

Thanks for considering a contribution.

## Getting started

```bash
bin/setup
bundle exec rspec
bundle exec rubocop
```

## The one rule

**An individual reviewer report must never contain another person's login.**
Peers appear only as unlabeled points in a distribution. This is asserted in
`spec/review_lens/presentation/individual_report_spec.rb`; if you change
anything in the individual report path, keep that spec passing.

## Guidelines

- New code should pass RuboCop clean. `.rubocop_todo.yml` records complexity
  inherited from the tool this gem was extracted from — please don't add to it.
- Specs must not shell out to the real `gh`. `spec_helper` blocks `Open3` by
  default; inject a fake executor (see `spec/support/fake_executor.rb`).
- Prefer raising a clear error over degrading to empty output. Silent empty
  results were the single worst failure mode of the tool this came from.
- If you add a metric, document what it means and its minimum sample size in
  the README table, and say plainly what it cannot tell you.

## A note on scope

This tool takes a position: metrics about people should be handed to those
people, not used to rank them. Features that make it easier to stack-rank a
team, or to hand one person's numbers to someone else, are out of scope.
