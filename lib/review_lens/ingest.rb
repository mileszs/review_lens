# frozen_string_literal: true

module ReviewLens
  # Populates the store from GitHub. This is `review-lens fetch`.
  #
  # The reporting side reads only from SQLite, so nothing renders until this
  # has run. Merged pull requests never change, so a second run over the same
  # window skips everything it already has.
  class Ingest
    # Yields progress so a CLI can show it without this class knowing about output.
    Progress = Struct.new(:total, :done, :pr_number, :skipped, keyword_init: true)

    def initialize(config:, cache:, client: nil)
      @config = config
      @cache = cache
      @client = client || GitHubClient.new(config.repo)
    end

    # @return [Hash] counts for the CLI to report
    def call(since:, until_time:, &progress)
      @client.ensure_available!
      prs = @client.fetch_merged_prs(
        base_branch: @config.base_branch, since: since, until_time: until_time
      )
      return empty_result if prs.empty?

      already = @config.fresh? ? [] : @cache.cached_pr_numbers(repo: repo, pr_numbers: prs.map { |pr| pr['number'] })
      store_all(prs, already.to_h { |n| [n, true] }, &progress)
    end

    private

    def repo = @config.repo

    def empty_result = { total: 0, fetched: 0, skipped: 0 }

    def store_all(prs, already, &progress)
      fetched = 0
      skipped = 0

      prs.each_with_index do |pr, index|
        number = pr['number']
        if already[number]
          skipped += 1
        else
          store_one(pr)
          fetched += 1
        end
        report(progress, prs.length, index + 1, number, !already[number].nil?)
      end

      { total: prs.length, fetched: fetched, skipped: skipped }
    end

    # One PR costs two extra API calls: issue events (for review requests) and
    # commits (for whether a changes-requested review led to more work).
    def store_one(pull_request)
      number = pull_request['number']
      @cache.store_pull_request(repo: repo, pr_data: pull_request)
      @cache.store_reviews(repo: repo, pr_number: number, reviews: pull_request['reviews'] || [])

      events = @client.fetch_pr_events(number)
      requests = @client.extract_review_requests(events)
      @cache.store_review_requests(repo: repo, pr_number: number, review_requests: requests) if requests.any?

      commits = @client.fetch_pr_commits(number)
      @cache.store_commits(repo: repo, pr_number: number, commits: commits) if commits.any?
    end

    def report(progress, total, done, number, skipped)
      return unless progress

      progress.call(Progress.new(total: total, done: done, pr_number: number, skipped: skipped))
    end
  end
end
