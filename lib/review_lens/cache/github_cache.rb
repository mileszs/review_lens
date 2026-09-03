# frozen_string_literal: true

require 'time'

module ReviewLens
  module Cache
    # Reads and writes the PR, review, review-request and commit rows that
    # reviewer metrics are computed from.
    #
    # Two conventions apply to every read here:
    #
    # 1. Attribution is by the pull request's merged_at, not the review's
    #    submitted_at: a review counts toward the period its PR merged in.
    # 2. Self-reviews are excluded. A comment on your own pull request is not
    #    a review of someone else's work, and counting it inflates review
    #    volume while leaving "PRs reviewed" at zero.
    class GithubCache
      def initialize(cache_store:)
        @db = cache_store.db
      end

      # Which of these PR numbers are already stored? Lets `fetch` skip work on
      # a re-run -- merged PRs are immutable.
      def cached_pr_numbers(repo:, pr_numbers:)
        return [] if pr_numbers.empty?

        placeholders = (['?'] * pr_numbers.length).join(',')
        @db.execute(
          "SELECT pr_number FROM github_pull_requests WHERE repo = ? AND pr_number IN (#{placeholders})",
          [repo, *pr_numbers]
        ).map { |row| row['pr_number'].to_i }
      end

      def store_pull_request(repo:, pr_data:)
        @db.execute(
          'INSERT OR REPLACE INTO github_pull_requests ' \
          '(repo, pr_number, title, author_login, is_draft, created_at, merged_at, ' \
          'additions, deletions, changed_files, cached_at) ' \
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            repo,
            pr_data['number'],
            pr_data['title'],
            pr_data.dig('author', 'login'),
            pr_data['isDraft'] ? 1 : 0,
            pr_data['createdAt'],
            pr_data['mergedAt'],
            pr_data['additions'],
            pr_data['deletions'],
            pr_data['changedFiles'],
            Time.now.utc.iso8601
          ]
        )
      end

      def store_reviews(repo:, pr_number:, reviews:)
        return if reviews.empty?

        @db.execute('DELETE FROM pr_reviews WHERE repo = ? AND pr_number = ?', [repo, pr_number])
        @db.transaction do
          reviews.each do |review|
            @db.execute(
              'INSERT INTO pr_reviews (repo, pr_number, reviewer_login, state, submitted_at, body) ' \
              'VALUES (?, ?, ?, ?, ?, ?)',
              [
                repo,
                pr_number,
                review.dig('author', 'login'),
                review['state'],
                review['submittedAt'],
                review['body']
              ]
            )
          end
        end
      end

      # Returns Array of { reviewer_login:, state:, count: } for reviews in date range
      def fetch_reviews_in_period(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.reviewer_login, r.state, COUNT(*) as count ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          'WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? AND r.reviewer_login IS NOT NULL ' \
          'AND r.reviewer_login != p.author_login ' \
          'GROUP BY r.reviewer_login, r.state',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            reviewer_login: row['reviewer_login'],
            state: row['state'],
            count: row['count']
          }
        end
      end

      # Returns Array of { reviewer_login:, state:, body: } for individual reviews in date range
      def fetch_review_bodies_in_period(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.reviewer_login, r.state, r.body ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          'WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? AND r.reviewer_login IS NOT NULL ' \
          'AND r.reviewer_login != p.author_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            reviewer_login: row['reviewer_login'],
            state: row['state'],
            body: row['body']
          }
        end
      end

      # Returns Array of { pr_number:, review_count: } for actionable reviews per PR in date range
      def fetch_review_counts_per_pr(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.pr_number, COUNT(*) as review_count ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          'WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? ' \
          "AND r.state IN ('APPROVED', 'CHANGES_REQUESTED') " \
          'AND r.reviewer_login != p.author_login ' \
          'GROUP BY r.pr_number',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            pr_number: row['pr_number'],
            review_count: row['review_count']
          }
        end
      end

      def store_commits(repo:, pr_number:, commits:)
        return if commits.empty?

        @db.execute('DELETE FROM pr_commits WHERE repo = ? AND pr_number = ?', [repo, pr_number])
        @db.transaction do
          commits.each do |commit|
            @db.execute(
              'INSERT INTO pr_commits (repo, pr_number, sha, author_login, committed_at) ' \
              'VALUES (?, ?, ?, ?, ?)',
              [repo, pr_number, commit[:sha], commit[:author_login], commit[:committed_at]]
            )
          end
        end
      end

      # Check if commits are cached for given PR numbers
      def commits_cached?(repo:, pr_numbers:)
        return false if pr_numbers.empty?

        placeholders = pr_numbers.map { '?' }.join(', ')
        result = @db.get_first_value(
          "SELECT COUNT(DISTINCT pr_number) FROM pr_commits WHERE repo = ? AND pr_number IN (#{placeholders})",
          [repo] + pr_numbers
        )
        result.to_i == pr_numbers.size
      end

      def store_review_requests(repo:, pr_number:, review_requests:)
        return if review_requests.empty?

        @db.execute('DELETE FROM pr_review_requests WHERE repo = ? AND pr_number = ?', [repo, pr_number])
        @db.transaction do
          review_requests.each do |request|
            @db.execute(
              'INSERT INTO pr_review_requests (repo, pr_number, requested_reviewer, requested_at) ' \
              'VALUES (?, ?, ?, ?)',
              [repo, pr_number, request[:requested_reviewer], request[:requested_at]]
            )
          end
        end
      end

      # Check if review requests are cached for given PR numbers
      def review_requests_cached?(repo:, pr_numbers:)
        return false if pr_numbers.empty?

        placeholders = pr_numbers.map { '?' }.join(', ')
        result = @db.get_first_value(
          "SELECT COUNT(DISTINCT pr_number) FROM pr_review_requests WHERE repo = ? AND pr_number IN (#{placeholders})",
          [repo] + pr_numbers
        )
        result.to_i == pr_numbers.size
      end

      # Fetch review requests for a specific PR
      def fetch_review_requests_for_pr(repo:, pr_number:)
        rows = @db.execute(
          'SELECT requested_reviewer, requested_at FROM pr_review_requests ' \
          'WHERE repo = ? AND pr_number = ? ORDER BY requested_at',
          [repo, pr_number]
        )

        rows.map do |row|
          {
            requested_reviewer: row['requested_reviewer'],
            requested_at: row['requested_at']
          }
        end
      end

      # Fetch all review requests in a date range, paired with first review response
      # Includes is_rerequest flag (true if same reviewer was previously requested on same PR)
      def fetch_reviewer_response_times(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT rr.requested_reviewer, rr.requested_at, rr.pr_number,   ' \
          '(SELECT MIN(r.submitted_at) FROM pr_reviews r    ' \
          'WHERE r.repo = rr.repo AND r.pr_number = rr.pr_number    ' \
          'AND r.reviewer_login = rr.requested_reviewer    ' \
          'AND r.submitted_at >= rr.requested_at) as first_review_at,   ' \
          '(SELECT COUNT(*) FROM pr_review_requests prev    ' \
          'WHERE prev.repo = rr.repo AND prev.pr_number = rr.pr_number    ' \
          'AND prev.requested_reviewer = rr.requested_reviewer    ' \
          'AND prev.requested_at < rr.requested_at) as prior_request_count ' \
          'FROM pr_review_requests rr ' \
          'JOIN github_pull_requests p ON rr.repo = p.repo AND rr.pr_number = p.pr_number ' \
          'WHERE rr.repo = ? AND p.merged_at BETWEEN ? AND ? ' \
          'AND rr.requested_reviewer != p.author_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            requested_reviewer: row['requested_reviewer'],
            requested_at: row['requested_at'],
            pr_number: row['pr_number'],
            first_review_at: row['first_review_at'],
            is_rerequest: row['prior_request_count'].to_i.positive?
          }
        end
      end

      # Returns Array of { reviewer_login:, pr_number:, review_submitted_at:, had_subsequent_commit: }
      # for CHANGES_REQUESTED reviews in date range
      def fetch_review_effectiveness(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.reviewer_login, r.pr_number, r.submitted_at,   ' \
          '(SELECT COUNT(*) FROM pr_commits c    ' \
          'WHERE c.repo = r.repo AND c.pr_number = r.pr_number    ' \
          'AND c.committed_at > r.submitted_at) as commits_after ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          "WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? AND r.state = 'CHANGES_REQUESTED' " \
          'AND r.reviewer_login != p.author_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            reviewer_login: row['reviewer_login'],
            pr_number: row['pr_number'],
            review_submitted_at: row['submitted_at'],
            had_subsequent_commit: row['commits_after'].to_i.positive?
          }
        end
      end

      # Returns Array of { reviewer_login:, author_login:, count: } for reviews in date range
      def fetch_review_author_pairs(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.reviewer_login, p.author_login, COUNT(*) as count ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          'WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? ' \
          'AND r.reviewer_login IS NOT NULL AND p.author_login IS NOT NULL ' \
          'AND r.reviewer_login != p.author_login ' \
          'GROUP BY r.reviewer_login, p.author_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            reviewer_login: row['reviewer_login'],
            author_login: row['author_login'],
            count: row['count']
          }
        end
      end

      # Returns Array of { author_login:, pr_count: } for PRs merged in date range
      def fetch_prs_authored_in_period(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT author_login, COUNT(*) as pr_count ' \
          'FROM github_pull_requests ' \
          'WHERE repo = ? AND merged_at BETWEEN ? AND ? ' \
          'AND author_login IS NOT NULL ' \
          'GROUP BY author_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            author_login: row['author_login'],
            pr_count: row['pr_count']
          }
        end
      end

      # Returns Array of { reviewer_login:, prs_reviewed: } for unique PRs reviewed in date range
      def fetch_unique_prs_reviewed_in_period(repo:, since:, until_time:)
        rows = @db.execute(
          'SELECT r.reviewer_login, COUNT(DISTINCT r.pr_number) as prs_reviewed ' \
          'FROM pr_reviews r ' \
          'JOIN github_pull_requests p ON r.repo = p.repo AND r.pr_number = p.pr_number ' \
          'WHERE r.repo = ? AND p.merged_at BETWEEN ? AND ? ' \
          'AND r.reviewer_login IS NOT NULL ' \
          'AND r.reviewer_login != p.author_login ' \
          'GROUP BY r.reviewer_login',
          [repo, since.iso8601, until_time.iso8601]
        )

        rows.map do |row|
          {
            reviewer_login: row['reviewer_login'],
            prs_reviewed: row['prs_reviewed']
          }
        end
      end
    end
  end
end
