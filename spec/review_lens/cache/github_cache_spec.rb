# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Cache::GithubCache do
  subject(:cache) { described_class.new(cache_store: cache_store) }

  let(:cache_store) { ReviewLens::Cache::Store.new(db_path: ':memory:') }
  let(:repo) { 'acme/widgets' }
  let(:sample_pr_data) do
    {
      'number' => 42,
      'title' => 'Fix login redirect',
      'author' => { 'login' => 'octocat' },
      'isDraft' => false,
      'createdAt' => '2025-06-01T09:00:00Z',
      'mergedAt' => '2025-06-02T15:30:00Z',
      'additions' => 120,
      'deletions' => 45,
      'changedFiles' => 8,
      'reviews' => [
        {
          'author' => { 'login' => 'reviewer1' },
          'state' => 'APPROVED',
          'submittedAt' => '2025-06-02T10:00:00Z',
          'body' => 'Looks good!'
        },
        {
          'author' => { 'login' => 'reviewer2' },
          'state' => 'CHANGES_REQUESTED',
          'submittedAt' => '2025-06-01T14:00:00Z',
          'body' => 'Please add tests'
        }
      ]
    }
  end
  let(:sample_pickup_time) do
    PickupTime.new(
      pr_number: 42,
      review_requested_time: Time.parse('2025-06-01T09:00:00Z'),
      first_review_time: Time.parse('2025-06-01T14:00:00Z')
    )
  end

  after { cache_store.close }

  describe '#store_pull_request' do
    it 'stores PR data in the database' do
      cache.store_pull_request(repo: repo, pr_data: sample_pr_data)

      row = cache_store.db.execute(
        'SELECT * FROM github_pull_requests WHERE repo = ? AND pr_number = ?',
        [repo, 42]
      ).first

      expect(row['repo']).to eq(repo)
      expect(row['pr_number']).to eq(42)
      expect(row['title']).to eq('Fix login redirect')
      expect(row['author_login']).to eq('octocat')
      expect(row['is_draft']).to eq(0)
      expect(row['created_at']).to eq('2025-06-01T09:00:00Z')
      expect(row['merged_at']).to eq('2025-06-02T15:30:00Z')
      expect(row['additions']).to eq(120)
      expect(row['deletions']).to eq(45)
      expect(row['changed_files']).to eq(8)
      expect(row['cached_at']).not_to be_nil
    end

    it 'updates existing PR on re-insert' do
      cache.store_pull_request(repo: repo, pr_data: sample_pr_data)

      updated = sample_pr_data.merge('title' => 'Updated title')
      cache.store_pull_request(repo: repo, pr_data: updated)

      rows = cache_store.db.execute(
        'SELECT * FROM github_pull_requests WHERE repo = ? AND pr_number = ?',
        [repo, 42]
      )
      expect(rows.length).to eq(1)
      expect(rows.first['title']).to eq('Updated title')
    end

    it 'handles draft PRs' do
      draft_pr = sample_pr_data.merge('isDraft' => true)
      cache.store_pull_request(repo: repo, pr_data: draft_pr)

      row = cache_store.db.execute(
        'SELECT is_draft FROM github_pull_requests WHERE repo = ? AND pr_number = ?',
        [repo, 42]
      ).first
      expect(row['is_draft']).to eq(1)
    end

    it 'handles nil optional fields' do
      minimal_pr = {
        'number' => 99,
        'title' => nil,
        'author' => nil,
        'isDraft' => false,
        'createdAt' => '2025-06-01T09:00:00Z',
        'mergedAt' => nil,
        'additions' => nil,
        'deletions' => nil,
        'changedFiles' => nil,
        'reviews' => []
      }

      expect { cache.store_pull_request(repo: repo, pr_data: minimal_pr) }.not_to raise_error
    end
  end

  describe '#store_reviews' do
    it 'stores review data for a PR' do
      reviews = sample_pr_data['reviews']
      cache.store_reviews(repo: repo, pr_number: 42, reviews: reviews)

      rows = cache_store.db.execute(
        'SELECT * FROM pr_reviews WHERE repo = ? AND pr_number = ? ORDER BY submitted_at',
        [repo, 42]
      )

      expect(rows.length).to eq(2)
      expect(rows[0]['reviewer_login']).to eq('reviewer2')
      expect(rows[0]['state']).to eq('CHANGES_REQUESTED')
      expect(rows[0]['body']).to eq('Please add tests')
      expect(rows[1]['reviewer_login']).to eq('reviewer1')
      expect(rows[1]['state']).to eq('APPROVED')
    end

    it 'replaces existing reviews on re-store' do
      reviews = sample_pr_data['reviews']
      cache.store_reviews(repo: repo, pr_number: 42, reviews: reviews)
      cache.store_reviews(repo: repo, pr_number: 42, reviews: [reviews.first])

      rows = cache_store.db.execute(
        'SELECT * FROM pr_reviews WHERE repo = ? AND pr_number = ?',
        [repo, 42]
      )
      expect(rows.length).to eq(1)
    end

    it 'does nothing for empty reviews' do
      expect { cache.store_reviews(repo: repo, pr_number: 42, reviews: []) }.not_to raise_error
    end
  end

  describe '#fetch_prs_authored_in_period' do
    let(:week_start) { Time.parse('2025-06-01T00:00:00Z') }
    let(:week_end) { Time.parse('2025-06-07T23:59:59Z') }

    before do
      # Insert PRs with different authors
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 1, 'title' => 'PR 1', 'author' => { 'login' => 'alice' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-01T09:00:00Z',
                                 'mergedAt' => '2025-06-02T10:00:00Z',
                                 'additions' => 10, 'deletions' => 5, 'changedFiles' => 2
                               })
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 2, 'title' => 'PR 2', 'author' => { 'login' => 'alice' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-02T09:00:00Z',
                                 'mergedAt' => '2025-06-03T10:00:00Z',
                                 'additions' => 20, 'deletions' => 10, 'changedFiles' => 4
                               })
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 3, 'title' => 'PR 3', 'author' => { 'login' => 'bob' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-03T09:00:00Z',
                                 'mergedAt' => '2025-06-04T10:00:00Z',
                                 'additions' => 5, 'deletions' => 2, 'changedFiles' => 1
                               })
    end

    it 'returns PR counts grouped by author' do
      result = cache.fetch_prs_authored_in_period(repo: repo, since: week_start, until_time: week_end)

      expect(result.length).to eq(2)

      alice = result.find { |r| r[:author_login] == 'alice' }
      expect(alice[:pr_count]).to eq(2)

      bob = result.find { |r| r[:author_login] == 'bob' }
      expect(bob[:pr_count]).to eq(1)
    end

    it 'excludes PRs outside the date range' do
      # Insert a PR outside the range
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 99, 'title' => 'Old PR', 'author' => { 'login' => 'charlie' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-05-01T09:00:00Z',
                                 'mergedAt' => '2025-05-02T10:00:00Z',
                                 'additions' => 1, 'deletions' => 1, 'changedFiles' => 1
                               })

      result = cache.fetch_prs_authored_in_period(repo: repo, since: week_start, until_time: week_end)

      authors = result.map { |r| r[:author_login] }
      expect(authors).not_to include('charlie')
    end

    it 'returns empty array when no PRs in range' do
      result = cache.fetch_prs_authored_in_period(
        repo: repo,
        since: Time.parse('2024-01-01T00:00:00Z'),
        until_time: Time.parse('2024-01-07T23:59:59Z')
      )

      expect(result).to eq([])
    end

    it 'excludes PRs with nil author_login' do
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 50, 'title' => 'No Author', 'author' => nil,
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-01T09:00:00Z',
                                 'mergedAt' => '2025-06-02T10:00:00Z',
                                 'additions' => 1, 'deletions' => 1, 'changedFiles' => 1
                               })

      result = cache.fetch_prs_authored_in_period(repo: repo, since: week_start, until_time: week_end)

      # Should only have alice and bob, not nil
      expect(result.length).to eq(2)
      expect(result.map { |r| r[:author_login] }).to contain_exactly('alice', 'bob')
    end
  end

  describe '#fetch_unique_prs_reviewed_in_period' do
    let(:week_start) { Time.parse('2025-06-01T00:00:00Z') }
    let(:week_end) { Time.parse('2025-06-07T23:59:59Z') }

    before do
      # Insert PRs
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 1, 'title' => 'PR 1', 'author' => { 'login' => 'alice' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-01T09:00:00Z',
                                 'mergedAt' => '2025-06-02T10:00:00Z',
                                 'additions' => 10, 'deletions' => 5, 'changedFiles' => 2
                               })
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 2, 'title' => 'PR 2', 'author' => { 'login' => 'alice' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-02T09:00:00Z',
                                 'mergedAt' => '2025-06-03T10:00:00Z',
                                 'additions' => 20, 'deletions' => 10, 'changedFiles' => 4
                               })
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => 3, 'title' => 'PR 3', 'author' => { 'login' => 'bob' },
                                 'isDraft' => false,
                                 'createdAt' => '2025-06-03T09:00:00Z',
                                 'mergedAt' => '2025-06-04T10:00:00Z',
                                 'additions' => 5, 'deletions' => 2, 'changedFiles' => 1
                               })

      # Insert reviews - charlie reviews PR 1 twice, PR 2 once
      cache.store_reviews(repo: repo, pr_number: 1, reviews: [
                            { 'author' => { 'login' => 'charlie' }, 'state' => 'CHANGES_REQUESTED',
                              'submittedAt' => '2025-06-01T10:00:00Z', 'body' => 'Fix this' },
                            { 'author' => { 'login' => 'charlie' }, 'state' => 'APPROVED',
                              'submittedAt' => '2025-06-01T14:00:00Z',
                              'body' => 'LGTM' }
                          ])
      cache.store_reviews(repo: repo, pr_number: 2, reviews: [
                            { 'author' => { 'login' => 'charlie' }, 'state' => 'APPROVED',
                              'submittedAt' => '2025-06-02T10:00:00Z', 'body' => 'Good' }
                          ])
      # dave reviews PR 3
      cache.store_reviews(repo: repo, pr_number: 3, reviews: [
                            { 'author' => { 'login' => 'dave' }, 'state' => 'APPROVED',
                              'submittedAt' => '2025-06-03T10:00:00Z', 'body' => 'Nice' }
                          ])
    end

    it 'returns unique PRs reviewed per reviewer' do
      result = cache.fetch_unique_prs_reviewed_in_period(repo: repo, since: week_start, until_time: week_end)

      # charlie reviewed 2 unique PRs (even though they left 3 reviews)
      charlie = result.find { |r| r[:reviewer_login] == 'charlie' }
      expect(charlie[:prs_reviewed]).to eq(2)

      # dave reviewed 1 PR
      dave = result.find { |r| r[:reviewer_login] == 'dave' }
      expect(dave[:prs_reviewed]).to eq(1)
    end

    it 'excludes self-reviews (author reviewing their own PR)' do
      # alice reviews her own PR
      cache.store_reviews(repo: repo, pr_number: 1, reviews: [
                            { 'author' => { 'login' => 'alice' }, 'state' => 'COMMENTED',
                              'submittedAt' => '2025-06-01T11:00:00Z',
                              'body' => 'Adding context' },
                            { 'author' => { 'login' => 'charlie' }, 'state' => 'APPROVED',
                              'submittedAt' => '2025-06-01T14:00:00Z',
                              'body' => 'LGTM' }
                          ])

      result = cache.fetch_unique_prs_reviewed_in_period(repo: repo, since: week_start, until_time: week_end)

      # alice should not appear as a reviewer (only reviewed her own PRs)
      logins = result.map { |r| r[:reviewer_login] }
      expect(logins).not_to include('alice')
    end

    it 'returns empty array when no reviews in range' do
      result = cache.fetch_unique_prs_reviewed_in_period(
        repo: repo,
        since: Time.parse('2024-01-01T00:00:00Z'),
        until_time: Time.parse('2024-01-07T23:59:59Z')
      )

      expect(result).to eq([])
    end
  end

  describe '#fetch_rereview_returns' do
    def add_pr(number, author:, merged_at: '2026-02-10T12:00:00Z')
      cache.store_pull_request(repo: repo, pr_data: {
                                 'number' => number, 'title' => "PR #{number}",
                                 'author' => { 'login' => author },
                                 'createdAt' => '2026-02-01T09:00:00Z', 'mergedAt' => merged_at
                               })
    end

    def add_review(number, login, state, at)
      cache.store_reviews(repo: repo, pr_number: number, reviews: [
                            { 'author' => { 'login' => login }, 'state' => state,
                              'submittedAt' => at, 'body' => 'x' }
                          ])
    end

    let(:window) { { repo: repo, since: Time.utc(2026, 1, 1), until_time: Time.utc(2026, 3, 1) } }

    it 'pairs a blocking review with the push that followed and the return' do
      add_pr(1, author: 'carol')
      cache.store_reviews(repo: repo, pr_number: 1, reviews: [
                            { 'author' => { 'login' => 'alice' }, 'state' => 'CHANGES_REQUESTED',
                              'submittedAt' => '2026-02-02T10:00:00Z', 'body' => 'please fix' },
                            { 'author' => { 'login' => 'alice' }, 'state' => 'APPROVED',
                              'submittedAt' => '2026-02-03T15:00:00Z', 'body' => 'thanks' }
                          ])
      cache.store_commits(repo: repo, pr_number: 1,
                          commits: [{ sha: 'a', author_login: 'carol', committed_at: '2026-02-03T09:00:00Z' }])

      rows = cache.fetch_rereview_returns(**window)

      expect(rows.length).to eq(1)
      expect(rows.first).to include(reviewer_login: 'alice', pr_number: 1,
                                    pushed_at: '2026-02-03T09:00:00Z',
                                    returned_at: '2026-02-03T15:00:00Z')
    end

    it 'records a wait with no return when the reviewer never came back' do
      add_pr(2, author: 'carol')
      add_review(2, 'alice', 'CHANGES_REQUESTED', '2026-02-02T10:00:00Z')
      cache.store_commits(repo: repo, pr_number: 2,
                          commits: [{ sha: 'b', author_login: 'carol', committed_at: '2026-02-03T09:00:00Z' }])

      rows = cache.fetch_rereview_returns(**window)

      expect(rows.first[:returned_at]).to be_nil
    end

    # Nobody was waiting on the reviewer, so it is not their wait to answer.
    it 'ignores a blocking review the author never pushed after' do
      add_pr(3, author: 'carol')
      add_review(3, 'alice', 'CHANGES_REQUESTED', '2026-02-02T10:00:00Z')

      expect(cache.fetch_rereview_returns(**window)).to be_empty
    end

    it 'ignores approvals, which hold nothing' do
      add_pr(4, author: 'carol')
      add_review(4, 'alice', 'APPROVED', '2026-02-02T10:00:00Z')
      cache.store_commits(repo: repo, pr_number: 4,
                          commits: [{ sha: 'c', author_login: 'carol', committed_at: '2026-02-03T09:00:00Z' }])

      expect(cache.fetch_rereview_returns(**window)).to be_empty
    end

    it 'ignores self-reviews' do
      add_pr(5, author: 'alice')
      add_review(5, 'alice', 'COMMENTED', '2026-02-02T10:00:00Z')
      cache.store_commits(repo: repo, pr_number: 5,
                          commits: [{ sha: 'd', author_login: 'alice', committed_at: '2026-02-03T09:00:00Z' }])

      expect(cache.fetch_rereview_returns(**window)).to be_empty
    end

    # A later review that predates the push is not a response to it.
    it 'treats a return that precedes the push as no return' do
      add_pr(6, author: 'carol')
      cache.store_reviews(repo: repo, pr_number: 6, reviews: [
                            { 'author' => { 'login' => 'alice' }, 'state' => 'COMMENTED',
                              'submittedAt' => '2026-02-02T10:00:00Z', 'body' => 'one' },
                            { 'author' => { 'login' => 'alice' }, 'state' => 'COMMENTED',
                              'submittedAt' => '2026-02-02T10:05:00Z', 'body' => 'two' }
                          ])
      cache.store_commits(repo: repo, pr_number: 6,
                          commits: [{ sha: 'e', author_login: 'carol', committed_at: '2026-02-04T09:00:00Z' }])

      rows = cache.fetch_rereview_returns(**window).select { |r| r[:pr_number] == 6 }

      expect(rows.map { |r| r[:returned_at] }).to all(be_nil)
    end
  end
end
