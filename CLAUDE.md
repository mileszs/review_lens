# CLAUDE.md — review_lens

Guidance for Claude Code when working in this repository.

## What this is

A Ruby gem that reads GitHub pull request reviews and produces two things:

1. **A team dashboard** — review volume, concentration, response times, depth.
2. **A private report for each reviewer** — that person's numbers against the
   team, handed to that person.

It was extracted from an internal engineering-scorecard tool and generalized.

## The point of view (read this before changing behavior)

This project takes a position, and the position constrains the code:

> Metrics about a person belong to that person. They are a prompt for a
> conversation, not evidence for a rating.

Concretely, that means:

- An individual's report **names only its subject**. Peers are unlabeled points.
- Comparisons are **direction-aware, not ranked**: "lower than 40% of the team",
  never "12th of 30". The code deliberately refuses to say which direction is
  better, because it doesn't know.
- Evaluative labels are **opt-in and team-report-only**.
- Below a minimum sample, the tool says "not enough activity" rather than
  producing a confident-looking number.

A change that makes it easier to stack-rank a team, or to hand one person's
numbers to someone else, is out of scope even if it's technically clean. If a
request seems to want that, say so and offer the narrower version.

## The invariant

**An individual report must never contain another person's login.**

Asserted in `spec/review_lens/presentation/individual_report_spec.rb`. If you
touch anything in the individual-report path, keep that spec passing. Don't
weaken it to make a feature fit.

## Architecture

Two phases, deliberately separate:

```
review-lens fetch     GitHub (gh CLI) ──> SQLite store
review-lens report    SQLite store ──> HTML
review-lens run       both
```

**`Analyzer` never calls GitHub.** It reads exclusively from the local store.
`Ingest` is the only thing that talks to the network. This is the single most
important structural fact here — if you find yourself adding an API call inside
an analysis or presentation class, you're in the wrong layer.

Reporting with an empty store raises `NoDataError` rather than rendering an
empty report. That failure mode (a plausible-looking but empty report) is the
main thing this design exists to prevent.

```
lib/review_lens/
├── cli.rb                  # option parsing + wiring only; no logic
├── configuration.rb        # every tunable; must never raise on missing config
├── errors.rb               # Error, GitHubCliError, CacheError, NoDataError,
│                           #   ConfigurationError
├── github_client.rb        # gh CLI wrapper; the only network boundary
├── ingest.rb               # `fetch`: walks merged PRs into the store
├── date_range.rb           # window resolution
├── cache/
│   ├── store.rb            # SQLite connection + schema (4 data tables)
│   └── github_cache.rb     # all SQL; reads for analysis, writes for ingest
├── analyzer.rb             # store rows -> the metrics hash
├── analysis/               # independent calculations the analyzer composes
│   ├── cross_team.rb       #   optional; nil when no teams configured
│   ├── response_times.rb   #   initial response to a review request
│   ├── rereviews.rb        #   coming back to a PR you held: speed + rate
│   └── effectiveness.rb    #   changes-requested -> subsequent commits
├── calculators/            # pure functions, no I/O
│   ├── median.rb           #   the only statistic the reviewer path needs
│   ├── business_hours.rb   #   configurable window/timezone; weekends only
│   ├── reviewer_percentiles.rb  # positions one person against the cohort
│   ├── review_distribution.rb   # gini / bus factor
│   ├── reviewer_flags.rb   #   evaluative; opt-in
│   └── heatmap_color.rb
├── models/                 # immutable value objects
│   ├── reviewer_stats.rb   #   #with(**changes) returns a copy
│   └── reviewer_response_time.rb
└── presentation/
    ├── data_mapper.rb      # metrics hash -> per-reviewer hashes for templates
    ├── team_report.rb      # the dashboard
    ├── individual_report.rb# the private per-person report
    ├── watch_list.rb       # evaluative; opt-in
    ├── anonymizer.rb       # stable stand-in names
    └── templates/          # ERB + inlined CSS/JS (self-contained output)
```

## Data shapes

`Analyzer#call` returns:

```ruby
{
  reviewer_stats:      [ReviewerStats],  # sorted by review volume desc
  total_reviewers:     Integer,
  total_reviews:       Integer,
  review_rounds:       { total_prs:, distribution:, median:, mean:, max: },
  distribution:        { gini:, bus_factor:, top_reviewer_share:, ... },
  cross_team:          Hash | nil,       # nil when no teams configured
  response_times:      Hash | nil,
  effectiveness:       Hash | nil,
  rereviews:           Hash | nil,       # coming back to PRs you held
  review_author_ratio: Hash | nil
}
```

`DataMapper#reviewers` returns one hash per person. Keys the individual report
compares on: `approval_pct`, `depth_pct`, `response_initial`, `ratio`,
`cross_team_rate` — each gated by a sample key (`actionable`, `total`,
`response_n`, `prs_authored`).

## Conventions that are easy to violate

**The vocabulary is "team", everywhere.** Hash keys, methods, comments, display
text, config. The tool this was extracted from called them squads; that name was
renamed out entirely before release, so `squad` appearing anywhere is a
regression. A group of people is a *team*; the config key is `teams`.

**Self-reviews are excluded everywhere.** Every read in `github_cache.rb`
filters `reviewer_login != author_login`. Commenting on your own PR is not a
review. A new query must do the same or it will disagree with the others — this
was a real bug: 9 "reviews" alongside 0 "PRs reviewed".

**Re-review is measured from the author's push, not from GitHub's "re-request
review" button.** Most teams never press it — on the repo this was extracted
from it produced 77 events in 90 days versus 442 reviewer-initiated returns — so
keying off it measures a convention rather than the behaviour. Starting at the
push also means a reviewer is never charged for the author's turnaround. A
non-approving review the author never pushed after is excluded entirely: nobody
was waiting.

**Attribution is by the PR's `merged_at`, not the review's `submitted_at`.** A
review counts toward the period its pull request merged in. Every query filters
this way; keep new ones consistent.

**Two independent guards on comparisons**, and both matter:
- minimum *sample* — does this person have enough activity? (`min_sample`)
- minimum *cohort* — are there enough other people? (`ReviewerPercentiles::MIN_COHORT`,
  currently 3). A cohort of one produced "higher than 0% of the team".

**Raise, don't degrade.** A missing/unauthenticated `gh`, an unreadable
database, an unfetched store — all raise a typed error with a next step. Never
`warn` and return `[]`; that is the bug this project was extracted to fix.

**People who authored PRs but reviewed nothing are included** with zero reviews.
That's deliberate — the review/author ratio is how you notice them. Someone with
zero reviews gets a plain "no review activity" page, not a wall of empty cards.

**Output is local and gitignored.** Reports name real people. `write_individual`
drops a `.gitignore` beside them. Nothing is uploaded anywhere.

## Configuration

`Configuration` is the single source of tunables: repo, base branch, window,
cache path, teams, bot logins, timezone + business hours, depth thresholds,
minimum sample, flags, output directory, anonymizer names.

Precedence: **CLI flag → ENV → `.review-lens.yml` → default.**

It must **never raise on a missing or malformed config file** — a first-time
user has neither a config file nor a team map. Adding a setting means: a key in
`FILE_FIELDS`, a default in `apply_defaults`, usually a CLI flag, and a line in
the README table.

Teams are optional. With none configured, `CrossTeam#call` returns `nil` and the
section is **omitted**, not rendered as zeroes. A team declared with no members
parses as `nil` from YAML — guard it (this crashed the original tool).

## Testing

```bash
bundle exec rspec
bundle exec rubocop
bundle exec rake        # both
```

- **Specs must never shell out to real `gh`.** `spec_helper` stubs `Open3` to
  raise. Inject `spec/support/fake_executor.rb` instead.
- Use `ReviewLens::Cache::Store.new(db_path: ':memory:')` for cache-backed specs. There are no
  fixtures, no VCR, no WebMock — data is hand-built hashes or in-memory rows.
- Use the `build_config` helper; it pins `config_path` to a nonexistent path so
  a real `.review-lens.yml` on the machine can't leak into a test.
- `spec_helper` deliberately does **not** silence stdout/stderr. The tool it came
  from did, which hid the exact failure mode described above.
- Use invented logins (`alice`, `bob`, …) and `acme/widgets`. Never real people
  or real repositories.

## Lint

RuboCop must pass clean. `.rubocop_todo.yml` records complexity **inherited**
from the extraction — it is debt to pay down, not a license. Don't add to it;
fix the code or restructure. If a cop genuinely doesn't fit (e.g. a single DDL
heredoc), configure it in `.rubocop.yml` with a comment saying why.

## Common tasks

**Add a metric.** Calculation in `calculators/` (pure) or `analysis/` (composes
store data) → wire into `Analyzer#breakdowns` → surface in `DataMapper` → render
in a template. If it should appear in the individual report, add it to
`IndividualReport.metric_definitions` with a `direction`, a `min_sample_key`,
and a plain-language `note`. Document it in the README table with its minimum
sample and say what it *cannot* tell you.

**Add a template asset.** The gemspec ships `lib/**/templates/**/*` — check a
new file type is matched, or it will work locally and vanish once installed.

**Change a report.** Templates are ERB rendered against the reporter's `binding`,
with CSS/JS inlined so output is self-contained and works offline. Don't add a
CDN link or external asset.

## Gotchas

- **Ruby version.** `.tool-versions` pins 3.4.6. A shell without asdf on `PATH`
  falls back to system Ruby 2.6 and fails confusingly on bundler. Use
  `export PATH="$HOME/.asdf/shims:$PATH"`.
- `gh pr list` caps at 1000 with no page flag. `fetch_merged_prs` splits the
  window when a page returns at the cap. Preserve that if you touch the client.
- Merged PRs are immutable, so `fetch` skips what it already has. `--fresh`
  bypasses it.
- Business hours skip weekends but have **no holiday calendar**. Say so rather
  than implying precision the code doesn't have.

## Release status

Not published. This was extracted from CareerPlug-internal tooling and needs
their sign-off before it goes public. Don't push to a remote, publish to
RubyGems, or add a git remote unless explicitly asked. Before any public
release, re-check for real logins, internal repo names, and credentials.
