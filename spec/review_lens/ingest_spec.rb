# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Ingest do
  subject(:ingest) { described_class.new(config: config, cache: cache, client: client) }

  let(:store) { ReviewLens::Cache::Store.new(db_path: ':memory:') }
  let(:cache) { ReviewLens::Cache::GithubCache.new(cache_store: store) }
  let(:config) { ReviewLens::Configuration.new(repo: 'acme/widgets', config_path: '/nonexistent') }
  let(:since) { Time.utc(2026, 1, 1) }
  let(:until_time) { Time.utc(2026, 4, 1) }

  let(:pull_requests) do
    [
      { 'number' => 1, 'title' => 'Add widget', 'author' => { 'login' => 'alice' },
        'createdAt' => '2026-02-01T10:00:00Z', 'mergedAt' => '2026-02-02T10:00:00Z',
        'reviews' => [{ 'author' => { 'login' => 'bob' }, 'state' => 'APPROVED',
                        'submittedAt' => '2026-02-01T15:00:00Z', 'body' => 'Looks good to me overall' }] }
    ]
  end

  let(:client) do
    instance_double(
      ReviewLens::GitHubClient,
      ensure_available!: true,
      fetch_merged_prs: pull_requests,
      fetch_pr_events: [{ 'event' => 'review_requested', 'created_at' => '2026-02-01T11:00:00Z',
                          'requested_reviewer' => { 'login' => 'bob' } }],
      extract_review_requests: [{ requested_reviewer: 'bob', requested_at: '2026-02-01T11:00:00Z' }],
      fetch_pr_commits: [{ sha: 'abc', author_login: 'alice', committed_at: '2026-02-01T16:00:00Z' }]
    )
  end

  after { store.close }

  it 'verifies the CLI is usable before doing any work' do
    ingest.call(since: since, until_time: until_time)

    expect(client).to have_received(:ensure_available!)
  end

  it 'stores pull requests and their reviews' do
    ingest.call(since: since, until_time: until_time)

    expect(store.db.get_first_value('SELECT COUNT(*) FROM github_pull_requests')).to eq(1)
    expect(store.db.get_first_value('SELECT COUNT(*) FROM pr_reviews')).to eq(1)
  end

  it 'stores review requests and commits' do
    ingest.call(since: since, until_time: until_time)

    expect(store.db.get_first_value('SELECT COUNT(*) FROM pr_review_requests')).to eq(1)
    expect(store.db.get_first_value('SELECT COUNT(*) FROM pr_commits')).to eq(1)
  end

  it 'reports what it did' do
    expect(ingest.call(since: since, until_time: until_time))
      .to eq(total: 1, fetched: 1, skipped: 0)
  end

  it 'yields progress' do
    seen = []
    ingest.call(since: since, until_time: until_time) { |p| seen << p }

    expect(seen.map(&:done)).to eq([1])
    expect(seen.first.total).to eq(1)
  end

  # Merged pull requests never change, so a second pass should cost nothing.
  describe 'incremental behaviour' do
    it 'skips pull requests already stored' do
      ingest.call(since: since, until_time: until_time)
      second = ingest.call(since: since, until_time: until_time)

      expect(second).to eq(total: 1, fetched: 0, skipped: 1)
    end

    it 'does not re-request details for stored pull requests' do
      ingest.call(since: since, until_time: until_time)
      ingest.call(since: since, until_time: until_time)

      expect(client).to have_received(:fetch_pr_commits).once
    end

    it 're-fetches everything when fresh is set' do
      ingest.call(since: since, until_time: until_time)
      fresh_config = ReviewLens::Configuration.new(repo: 'acme/widgets', config_path: '/nonexistent', fresh: true)
      result = described_class.new(config: fresh_config, cache: cache, client: client)
                              .call(since: since, until_time: until_time)

      expect(result).to eq(total: 1, fetched: 1, skipped: 0)
    end
  end

  context 'when the window has no merged pull requests' do
    it 'returns zeroes without touching the database' do
      allow(client).to receive(:fetch_merged_prs).and_return([])

      expect(ingest.call(since: since, until_time: until_time)).to eq(total: 0, fetched: 0, skipped: 0)
      expect(store).to be_empty
    end
  end
end
