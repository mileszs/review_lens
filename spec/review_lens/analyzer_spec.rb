# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Analyzer do
  subject(:metrics) do
    described_class.new(config: config(teams: teams), cache: cache).call(since: since, until_time: until_time)
  end

  let(:store) { ReviewLens::Cache::Store.new(db_path: ':memory:') }
  let(:cache) { ReviewLens::Cache::GithubCache.new(cache_store: store) }
  let(:repo) { 'acme/widgets' }
  let(:since) { Time.utc(2026, 1, 1) }
  let(:until_time) { Time.utc(2026, 4, 1) }
  let(:teams) { { 'platform' => %w[alice bob], 'product' => %w[carol] } }

  def config(**overrides)
    ReviewLens::Configuration.new(repo: repo, config_path: '/nonexistent', **overrides)
  end

  def add_pr(number, author:, merged_at: '2026-02-01T12:00:00Z')
    store.db.execute(
      'INSERT INTO github_pull_requests (repo, pr_number, title, author_login, merged_at, cached_at) ' \
      'VALUES (?, ?, ?, ?, ?, ?)',
      [repo, number, "PR #{number}", author, merged_at, Time.now.utc.iso8601]
    )
  end

  def add_review(number, reviewer:, state: 'APPROVED', body: 'x' * 150, at: '2026-02-01T11:00:00Z')
    store.db.execute(
      'INSERT INTO pr_reviews (repo, pr_number, reviewer_login, state, submitted_at, body) ' \
      'VALUES (?, ?, ?, ?, ?, ?)',
      [repo, number, reviewer, state, at, body]
    )
  end

  after { store.close }

  context 'with reviews in the window' do
    before do
      add_pr(1, author: 'carol')
      add_review(1, reviewer: 'alice')
      add_pr(2, author: 'carol')
      add_review(2, reviewer: 'alice', state: 'CHANGES_REQUESTED')
      add_pr(3, author: 'alice')
      add_review(3, reviewer: 'bob', body: 'Looks reasonable, one thought inline.')
    end

    # People who authored PRs but reviewed nothing are included with zero
    # reviews: the review/author ratio is exactly how you notice them.
    it 'counts everyone involved, including authors who never reviewed' do
      expect(metrics[:total_reviewers]).to eq(3)
      expect(metrics[:total_reviews]).to eq(3)
    end

    it 'returns reviewer stats sorted by review volume' do
      expect(metrics[:reviewer_stats].map(&:reviewer_login)).to eq(%w[alice bob carol])
    end

    it 'records authored PR counts alongside review counts' do
      carol = metrics[:reviewer_stats].find { |s| s.reviewer_login == 'carol' }

      expect(carol.total_reviews).to eq(0)
      expect(carol.prs_authored).to eq(2)
    end

    it 'separates approvals from change requests' do
      alice = metrics[:reviewer_stats].find { |s| s.reviewer_login == 'alice' }

      expect(alice.approved_count).to eq(1)
      expect(alice.changes_requested_count).to eq(1)
    end

    it 'categorises review depth from the comment body' do
      alice = metrics[:reviewer_stats].find { |s| s.reviewer_login == 'alice' }
      bob = metrics[:reviewer_stats].find { |s| s.reviewer_login == 'bob' }

      expect(alice.substantive_count).to eq(2)
      expect(bob.brief_count).to eq(1)
    end

    it 'computes the distribution across reviewers' do
      expect(metrics[:distribution]).to include(:gini, :bus_factor)
    end

    it 'includes cross-team data when teams are configured' do
      expect(metrics[:cross_squad]).not_to be_nil
    end
  end

  context 'when no teams are configured' do
    before do
      add_pr(1, author: 'carol')
      add_review(1, reviewer: 'alice')
    end

    it 'omits cross-team data rather than reporting zeroes' do
      result = described_class.new(config: config, cache: cache).call(since: since, until_time: until_time)

      expect(result[:cross_squad]).to be_nil
    end
  end

  # The upstream analyzer returned an empty metrics hash when nothing was
  # cached, which rendered a plausible-looking but empty report.
  context 'when nothing has been fetched' do
    it 'raises instead of producing an empty report' do
      expect { metrics }.to raise_error(ReviewLens::NoDataError, /review-lens fetch/)
    end
  end

  context 'when reviews fall outside the window' do
    before do
      add_pr(1, author: 'carol', merged_at: '2025-06-01T12:00:00Z')
      add_review(1, reviewer: 'alice')
    end

    it 'raises, because the window has no data' do
      expect { metrics }.to raise_error(ReviewLens::NoDataError)
    end
  end

  # Attribution is by the PR's merge date, not the review's submission date.
  it 'attributes a review to the period its pull request merged' do
    add_pr(1, author: 'carol', merged_at: '2026-02-15T12:00:00Z')
    add_review(1, reviewer: 'alice', at: '2026-01-05T09:00:00Z')

    result = described_class.new(config: config, cache: cache).call(
      since: Time.utc(2026, 2, 1), until_time: Time.utc(2026, 3, 1)
    )

    expect(result[:total_reviews]).to eq(1)
  end
end
