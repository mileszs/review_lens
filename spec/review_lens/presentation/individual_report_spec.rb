# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Presentation::IndividualReport do
  let(:week_start) { Time.parse('2026-06-01 00:00:00 UTC') }
  let(:week_end) { Time.parse('2026-08-31 00:00:00 UTC') }
  let(:config) { build_config(repo: 'acme/widgets') }
  let(:reviewer_stats) do
    [
      stats('alice', approved: 45, changes: 12, commented: 30, minimal: 40, brief: 25, substantive: 22, authored: 15),
      stats('bob',   approved: 30, changes: 5,  commented: 15, minimal: 30, brief: 10, substantive: 10, authored: 20),
      stats('carol', approved: 20, changes: 10, commented: 5,  minimal: 10, brief: 8,  substantive: 14, authored: 12),
      # dave is intentionally sparse (no response/ratio/cross-team sub-hash entries)
      stats('dave',  approved: 8,  changes: 1,  commented: 2,  minimal: 6,  brief: 3,  substantive: 2,  authored: 30),
      stats('github-actions', approved: 0, changes: 0, commented: 100, minimal: 100, brief: 0, substantive: 0,
                              authored: 0)
    ]
  end
  let(:metrics) do
    {
      reviewer_stats: reviewer_stats, total_reviewers: 5, total_reviews: 330,
      review_rounds: { total_prs: 150, distribution: { 1 => 120, 2 => 25, '3+' => 5 }, median: 1, mean: 1.3, max: 4 },
      distribution: { gini: 0.35, bus_factor: 4, top_reviewer_share: 22, top_3_share: 55, health: :healthy },
      cross_team: { same_team_reviews: 100, cross_team_reviews: 80, external_reviews: 57, cross_team_rate: 44.4,
                    reviewer_stats: [
                      { reviewer_login: 'alice', same_team: 20, cross_team: 37, cross_team_rate: 64.9 },
                      { reviewer_login: 'bob', same_team: 30, cross_team: 20, cross_team_rate: 40.0 },
                      { reviewer_login: 'carol', same_team: 25, cross_team: 10, cross_team_rate: 28.6 }
                    ] },
      response_times: { overall_median_hours: 1.2, total_requests: 200, responded_count: 150,
                        reviewer_stats: [
                          { reviewer_login: 'alice', median_hours: 0.8, review_count: 45 },
                          { reviewer_login: 'bob', median_hours: 2.5, review_count: 35 },
                          { reviewer_login: 'carol', median_hours: 1.5, review_count: 30 }
                        ],
                        rereview_metrics: { reviewer_stats: [{ reviewer_login: 'alice', median_hours: 0.6 }] },
                        comparison_stats: [{ reviewer_login: 'alice', delta_hours: -0.2 }] },
      effectiveness: { total_changes_requested: 27, total_effective: 18, overall_effectiveness_rate: 66.7,
                       reviewer_stats: [{ reviewer_login: 'alice', effective_count: 8, effectiveness_rate: 66.7 }] },
      review_author_ratio: { stats: [
        { login: 'alice', prs_reviewed: 87, prs_authored: 15, ratio: 580.0 },
        { login: 'bob', prs_reviewed: 50, prs_authored: 20, ratio: 250.0 },
        { login: 'carol', prs_reviewed: 35, prs_authored: 12, ratio: 291.7 }
      ], total_people: 3, high_ratio_count: 3, low_ratio_count: 0 }
    }
  end

  def stats(login, approved:, changes:, commented:, minimal:, brief:, substantive:, authored:)
    ReviewLens::Models::ReviewerStats.new(
      reviewer_login: login, approved_count: approved, changes_requested_count: changes,
      commented_count: commented, minimal_count: minimal, brief_count: brief,
      substantive_count: substantive, prs_authored: authored
    )
  end

  def report_for(login)
    described_class.new(metrics: metrics, focus_login: login, week_start: week_start, week_end: week_end,
                        config: config)
  end

  describe '#render' do
    subject(:html) { report_for('alice').render }

    it 'renders a valid, self-contained document focused on the person' do
      expect(html).to include('<!DOCTYPE html>')
      expect(html).to include('alice')
      expect(html).to include('Approval rate').and include('team median')
      expect(html).to include('<style>') # inlined CSS, no external asset refs
    end

    # THE privacy property: an individual's report must not leak any other
    # reviewer's identity. Peers appear only as unlabeled distribution dots.
    it 'never contains another reviewer or bot login' do
      %w[bob carol dave github-actions].each do |other|
        expect(html).not_to include(other)
      end
    end

    it 'shows a neutral, direction-aware comparison' do
      # approval (higher-is-more) reads "higher than X%"; response time
      # (lower-is-faster) reads "lower than X%" — never mislabeling the fastest
      # responder as worst.
      expect(html).to include('higher than')
      expect(html).to include('lower than')
    end

    it 'renders without error for a reviewer missing optional data, degrading those metrics' do
      sparse = report_for('dave')
      expect { sparse.render }.not_to raise_error
      # dave has no response/ratio/cross-team entries -> those cards say so
      expect(sparse.render).to include('Not enough of your activity')
    end

    it 'produces a "no activity" page for a reviewer with zero reviews' do
      silent = ReviewLens::Models::ReviewerStats.new(reviewer_login: 'quiet', prs_authored: 4)
      metrics_with_silent = metrics.merge(reviewer_stats: reviewer_stats + [silent])
      html = described_class.new(
        metrics: metrics_with_silent, focus_login: 'quiet',
        week_start: week_start, week_end: week_end, config: config
      ).render

      expect(html).to include('No review activity')
      expect(html).to include('You authored 4 pull requests')
      expect(html).not_to include('Not enough of your activity')
    end

    it 'produces a "no activity" page for a login with no reviews' do
      html = report_for('ghost').render
      expect(html).to include('No review activity')
      expect(html).to include('ghost')
    end
  end
end
