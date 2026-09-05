# review_lens

Humane code review metrics from GitHub pull requests — including a **private
report for each reviewer that names only that person**.

Most review analytics rank a team against itself and hand the leaderboard to a
manager. This does something narrower and, I think, more useful: it describes
one person's review habits, positions them against the team without naming
anyone else, and leaves the judgement to the humans having the conversation.

---

## What it produces

**A team dashboard** — review volume and concentration (Gini, bus factor),
review rounds per PR, response times, review depth, and cross-team review flow.

**One private report per reviewer** — their volume, approval rate, review depth,
response time, and review/author ratio, each shown as *your value* against the
*team median*, with the rest of the team as **unlabeled dots** in a distribution
strip. Comparisons are direction-aware: a fast responder reads "lower than 80%
of the team", not "ranked 12th".

These are separate on purpose. The dashboard is for looking at the system. The
individual report is for handing to one person.

---

## Install

Requires **Ruby 3.1+** and the [GitHub CLI](https://cli.github.com), which
supplies both the data and the authentication.

```bash
gem install review_lens
gh auth login          # if you haven't already
```

## Quickstart

```bash
review-lens run --repo rails/rails --days 30
```

That fetches merged PRs into a local SQLite store, then writes:

```
review-lens/
├── team.html                 # the team dashboard
└── reviewers/
    ├── .gitignore            # these name real people; kept out of git
    ├── alice.html
    └── bob.html
```

`run` is `fetch` then `report`. Split them when you want to re-render without
re-fetching:

```bash
review-lens fetch  --repo owner/name --days 90   # slow: talks to GitHub
review-lens report --repo owner/name --days 90   # fast: reads the local store
```

Fetching is incremental — merged pull requests never change, so a second run
over the same window only picks up what's new.

---

## How to use these humanely

This is the part that matters more than the code.

**Give each person only their own report.** That is the entire reason peers are
unlabeled. A report that lets someone rank themselves against named colleagues
is a different, worse product.

**Don't feed these into performance review.** Review metrics measure a habit
inside a system — a team's PR size, its release pressure, who happens to own the
gnarly subsystem. They are a decent prompt for a conversation and poor evidence
for a rating.

**Read the direction, not the rank.** "Higher approval rate" is not better or
worse; it might mean trust, or it might mean rubber-stamping, and only the
person and their team know which. The tool deliberately declines to tell you.

**Small samples lie.** Each metric has a minimum sample and simply says "not
enough of your activity in this window to compare" below it. Resist the urge to
lower the threshold.

**Evaluative labels are off by default.** `--show-flags` will add
"rubber stamp" / "load bearing" / "under contributing" badges to the *team*
report. They never appear in an individual's own report. They're off because a
label attached to a name invites a judgement the data can't support on its own.
Turn them on only if you've decided how you'd act on them.

A reasonable use: read your own report first. Then offer it to each person as
something to talk about, not something to answer for.

---

## Configuration

Every setting can come from a flag, an environment variable, or a
`.review-lens.yml` in your project (or home) directory. Flags win.

```yaml
repo: owner/name
base_branch: main
days: 90

# Working hours used for response-time metrics, so an overnight or weekend
# wait doesn't read as neglect.
timezone: America/New_York
business_start_hour: 8
business_end_hour: 18

# Optional. Without it, the cross-team section is omitted entirely.
teams:
  platform: [alice, bob]
  product: [carol]

# Logins matched exactly; anything ending in "[bot]" is always excluded.
bot_logins: [github-actions, dependabot, renovate]

# What counts as a substantive review comment, in characters.
minimal_threshold: 10
substantive_threshold: 100

# Minimum activity before a person is compared to the team.
min_sample: 5

show_flags: false
output_dir: review-lens
```

| Flag | Description |
|---|---|
| `--repo OWNER/NAME` | Repository to analyze (required) |
| `--days N` | Rolling window, default 90 |
| `--since / --until` | Explicit window (`YYYY-MM-DD`) |
| `--login LOGIN` | Build only one person's report |
| `--only a,b` | Build reports for a subset |
| `--out DIR` | Output directory |
| `--no-team` / `--no-individual` | Build only one kind of report |
| `--anonymize` | Also write a team report with logins replaced |
| `--show-flags` | Include evaluative labels in the team report |
| `--fresh` | Re-fetch everything, ignoring the store |
| `--db PATH` | SQLite location (default `~/.review-lens/cache.db`) |

Environment: `REVIEW_LENS_REPO`, `REVIEW_LENS_DB`, `REVIEW_LENS_TZ`, `FRESH=true`.

---

## What each metric means

| Metric | Definition | Minimum sample |
|---|---|---|
| **Reviews** | Approvals + change requests + comment-only reviews | — |
| **Approval rate** | Approvals as a share of *actionable* reviews (approve + request changes). Comment-only reviews are excluded. | 5 actionable |
| **Substantive depth** | Share of reviews whose comment exceeds the substantive threshold. Length is a crude proxy for engagement. | 5 reviews |
| **Initial response time** | Median **business hours** from review request to first review. | 2 requests |
| **Re-review response time** | Median business hours to come back to a PR you held — you requested changes or commented without approving, and the author then pushed. The clock starts at **their push**, not your review. | 3 returns |
| **Return rate** | How often you came back at all after holding a PR and the author pushed. | 3 waits |
| **Review / author ratio** | PRs reviewed as a percentage of PRs authored. 100% means you review as many as you write. | 5 authored |
| **Cross-team reviews** | Share of reviews on PRs authored outside your team. Requires a team map. | — |
| **Gini / bus factor** | How concentrated reviewing is across the team. | — |
| **Review effectiveness** | How often a "changes requested" review was followed by more commits. A proxy, not a verdict. | — |

**Why re-review is measured from the push.** GitHub has a "re-request review"
button, but most teams don't use it — authors just push and reviewers come back.
Keying off the button measures a convention rather than the behaviour, so this
starts the clock when the author pushes instead. A reviewer is never charged for
the days an author spent making the changes.

Speed and follow-through are shown separately on purpose: a good median can hide
the threads someone never returned to. Not returning is not automatically a
failure — someone else may have approved, or the comment may not have been
blocking — and the reports say so.

Two things worth knowing:

- **Attribution is by merge date.** A review counts toward the period in which
  its pull request *merged*, not when the review was submitted.
- **Business hours skip weekends but not holidays.** A request spanning a public
  holiday will overstate elapsed working time.

People who authored PRs but reviewed nothing appear with zero reviews — that's
deliberate, since the review/author ratio is how you notice them.

---

## Privacy

An individual report contains only its subject. No peer login appears anywhere
in the file — not in the distribution strip, not in the HTML source. This is
[asserted in the test suite](spec/review_lens/presentation/individual_report_spec.rb)
and is the property most worth protecting if you send a patch.

Reports are written to a local directory with a `.gitignore` in it, and nothing
is uploaded anywhere. The `--anonymize` team report exists for when you want to
show shape without showing people.

---

## Troubleshooting

**`GitHub CLI (gh) was not found on your PATH`** — install from
<https://cli.github.com>.

**`GitHub CLI is not authenticated`** — run `gh auth login`.

**`No data stored yet. Run: review-lens fetch`** — reports read from the local
store, which `fetch` populates. This is deliberate: an unfetched report used to
come back empty and look real.

**Response times look wrong** — check `timezone`, `business_start_hour` and
`business_end_hour`. They default to US Eastern office hours.

**Someone is missing from the reports** — they may be classified as a bot.
Bot detection matches `bot_logins` exactly, plus any login ending in `[bot]`.

**A big repo seems to be missing PRs** — it shouldn't be; `gh pr list` caps at
1000 per query, so the window is split automatically. Please file a bug if you
see truncation.

---

## Development

```bash
bin/setup            # or: bundle install
bundle exec rspec
bundle exec rubocop
```

`.rubocop_todo.yml` records complexity inherited from the tool this was
extracted from. Please don't add to it — new code should pass clean.

## Contributing

Bug reports and pull requests are welcome. If you're changing anything in the
individual report, keep the privacy spec passing.

## License

MIT. See [LICENSE](LICENSE).
