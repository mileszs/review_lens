# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

First release. Extracted from an internal engineering-metrics tool and
generalized.

### Added
- `review-lens fetch` pulls merged pull requests, reviews, review requests and
  commits from GitHub (via the `gh` CLI) into a local SQLite store.
- `review-lens report` builds a team dashboard and a private HTML report for
  each reviewer. `review-lens run` does both.
- Private per-reviewer reports: each names only its subject. Peers appear as
  unlabeled points in a distribution, and comparisons are direction-aware
  ("lower than 40% of the team" for response time) rather than ranked.
- Optional team map for cross-team review analysis. Omit it and the section is
  left out rather than reported as zeroes.
- Optional anonymized team report.
- **Re-review response time and return rate.** After someone requests changes
  (or comments without approving) and the author pushes, somebody is waiting on
  that reviewer. Both reports now show how quickly they come back and how often
  they come back at all, measured from the author's push so a reviewer is not
  charged for the author's turnaround.
- Configuration via `.review-lens.yml`, environment, or CLI flags: working
  hours and timezone, bot logins, review-depth thresholds, minimum sample size,
  base branch, and output directory.

### Changed from the internal tool
- **Failures raise.** A missing or unauthenticated `gh` previously warned and
  returned no rows, producing an empty report that looked real. It now raises.
- **Pagination.** `gh pr list` caps at 1000 results with no page flag; the
  window is now split when a page comes back at the cap, instead of silently
  truncating.
- **Evaluative labels are opt-in** (`--show-flags`) and appear only in the team
  report, never in an individual's own report.
- **Bot detection is anchored.** A login is a bot when it equals a known bot
  name, begins with one followed by `-` or `[`, or ends with `[bot]`. The
  previous substring match classified a human login such as `precursor` as a
  bot; a naive exact match missed real ones like
  `copilot-pull-request-reviewer`.
- **Self-reviews are excluded consistently.** Previously only 2 of 8 queries
  filtered them, so commenting on your own pull request inflated your review
  count while leaving "PRs reviewed" at zero. A comment on your own PR is no
  longer counted as a review anywhere.
- **A comparison needs a real cohort.** Metrics are compared against the team
  only when at least three people qualify. Previously a cohort of one produced
  "higher than 0% of the team · 1 reviewers".
- **Reviewers with no reviews get a plain "no review activity" page** instead of
  a page of empty comparison cards.
- **Medians are true medians.** Even-sized sets previously took the upper
  middle value; they are now averaged. Figures may differ slightly from the
  internal tool for even-sized samples.
- Business hours, timezone, and depth thresholds are configurable rather than
  hardcoded to 8am-6pm US Eastern.
- **"Squad" is renamed to "team" throughout**, including the metrics hash keys
  (`cross_team`, `same_team_reviews`, `cross_team_rate`). The internal tool used
  its own org's word for a group of people; nothing in the public gem does.
- No third-party font CDN: reports are fully self-contained and render offline.

### Known limitations
- Business-hours math skips weekends but has no holiday calendar.
- Reviews are attributed to the period in which their pull request *merged*,
  not when the review was submitted.
