# frozen_string_literal: true

module ReviewLens
  # Turns stored PR/review rows into the metrics hash both reports render from.
  #
  # Reads only from the local store -- `Ingest` is what talks to GitHub. If
  # nothing has been fetched yet this raises NoDataError rather than quietly
  # producing an empty report.
  #
  # The independent calculations live in Analysis::*; this class fetches,
  # aggregates per reviewer, and assembles.
  class Analyzer
    STATE_FIELDS = {
      'APPROVED' => :approved_count,
      'CHANGES_REQUESTED' => :changes_requested_count,
      'COMMENTED' => :commented_count
    }.freeze

    def initialize(config:, cache:)
      @config = config
      @cache = cache
    end

    # @return [Hash] the metrics hash consumed by DataMapper
    def call(since:, until_time:)
      data = fetch_data(since: since, until_time: until_time)
      raise NoDataError, no_data_message if data[:aggregated].empty?

      analyze(data)
    end

    private

    def repo = @config.repo

    def no_data_message
      "No reviews found for #{repo} in this window. " \
        'If you have not fetched yet, run: review-lens fetch'
    end

    def fetch_data(since:, until_time:)
      window = { repo: repo, since: since, until_time: until_time }
      {
        aggregated: @cache.fetch_reviews_in_period(**window),
        individual: @cache.fetch_review_bodies_in_period(**window),
        per_pr: @cache.fetch_review_counts_per_pr(**window),
        review_pairs: @cache.fetch_review_author_pairs(**window),
        response_times: @cache.fetch_reviewer_response_times(**window),
        effectiveness: @cache.fetch_review_effectiveness(**window),
        prs_authored: @cache.fetch_prs_authored_in_period(**window),
        prs_reviewed: @cache.fetch_unique_prs_reviewed_in_period(**window)
      }
    end

    def analyze(data)
      stats = aggregate_by_reviewer(data[:aggregated])
      add_depth_data(stats, data[:individual] || [])
      add_author_data(stats, data[:prs_authored] || [])

      sorted = stats.values.sort_by { |stat| -stat.total_reviews }

      totals(sorted).merge(breakdowns(data, sorted))
    end

    def totals(sorted)
      {
        reviewer_stats: sorted,
        total_reviewers: sorted.size,
        total_reviews: sorted.sum(&:total_reviews)
      }
    end

    def breakdowns(data, sorted)
      {
        review_rounds: calculate_review_rounds(data[:per_pr] || []),
        distribution: calculate_distribution(sorted),
        cross_team: Analysis::CrossTeam.new(@config).call(data[:review_pairs] || []),
        response_times: Analysis::ResponseTimes.new(business_hours: business_hours).call(data[:response_times] || []),
        effectiveness: Analysis::Effectiveness.call(data[:effectiveness] || []),
        review_author_ratio: calculate_review_author_ratio(data[:prs_reviewed] || [], data[:prs_authored] || [])
      }
    end

    def business_hours
      @business_hours ||= Calculators::BusinessHours.new(
        timezone: @config.timezone,
        start_hour: @config.business_start_hour,
        end_hour: @config.business_end_hour
      )
    end

    # Review rows arrive grouped by (reviewer, state); fold them into one
    # ReviewerStats per person.
    def aggregate_by_reviewer(review_rows)
      totals = Hash.new { |hash, login| hash[login] = Hash.new(0) }

      review_rows.each do |row|
        field = STATE_FIELDS[row[:state]]
        next unless field

        totals[row[:reviewer_login]][field] += row[:count]
      end

      totals.to_h { |login, counts| [login, Models::ReviewerStats.new(reviewer_login: login, **counts)] }
    end

    def add_depth_data(reviewer_stats, individual_reviews)
      depth_counts = individual_reviews.each_with_object({}) do |review, hash|
        login = review[:reviewer_login]
        hash[login] ||= { minimal_count: 0, brief_count: 0, substantive_count: 0 }
        hash[login][:"#{categorize(review[:body])}_count"] += 1
      end

      depth_counts.each do |login, counts|
        next unless reviewer_stats[login]

        reviewer_stats[login] = reviewer_stats[login].with(**counts)
      end
    end

    def categorize(body)
      Models::ReviewerStats.categorize_depth(
        body, minimal: @config.minimal_threshold, substantive: @config.substantive_threshold
      )
    end

    def add_author_data(reviewer_stats, prs_authored_rows)
      author_counts = prs_authored_rows.to_h { |row| [row[:author_login], row[:pr_count]] }

      reviewer_stats.each_key do |login|
        reviewer_stats[login] = reviewer_stats[login].with(prs_authored: author_counts[login] || 0)
      end

      # People who authored PRs but reviewed nothing still belong in the data:
      # the review/author ratio is how you notice them.
      author_counts.each do |login, pr_count|
        next if reviewer_stats.key?(login)

        reviewer_stats[login] = Models::ReviewerStats.new(reviewer_login: login, prs_authored: pr_count)
      end
    end

    def calculate_review_rounds(per_pr_reviews)
      return { total_prs: 0, distribution: {}, median: nil, mean: nil } if per_pr_reviews.empty?

      counts = per_pr_reviews.map { |r| r[:review_count] }
      total = counts.size

      # Distribution buckets
      distribution = {
        1 => counts.count { |c| c == 1 },
        2 => counts.count { |c| c == 2 },
        '3+' => counts.count { |c| c >= 3 }
      }

      # Statistics
      sorted = counts.sort
      median = sorted[total / 2]
      mean = (counts.sum.to_f / total).round(2)

      {
        total_prs: total,
        distribution: distribution,
        median: median,
        mean: mean,
        max: sorted.last
      }
    end

    def calculate_distribution(sorted_stats)
      review_counts = sorted_stats.map(&:total_reviews)
      return nil if review_counts.empty?

      calc = Calculators::ReviewDistribution.new(review_counts)

      {
        gini: calc.gini_coefficient.round(2),
        bus_factor: calc.bus_factor,
        top_reviewer_share: calc.top_reviewer_share,
        top_3_share: calc.top_n_share(3),
        health: calc.health_rating
      }
    end

    def calculate_review_author_ratio(prs_reviewed_rows, prs_authored_rows)
      # Include all people who either reviewed or authored PRs
      all_logins = (prs_reviewed_rows.map { |r| r[:reviewer_login] } + prs_authored_rows.map do |r|
        r[:author_login]
      end).uniq
      return nil if all_logins.empty?

      author_counts = prs_authored_rows.to_h { |row| [row[:author_login], row[:pr_count]] }
      reviewed_counts = prs_reviewed_rows.to_h { |row| [row[:reviewer_login], row[:prs_reviewed]] }

      stats = all_logins.map do |login|
        prs_reviewed = reviewed_counts[login] || 0
        authored = author_counts[login] || 0
        ratio = authored.positive? ? (prs_reviewed.to_f / authored * 100).round(0).to_i : nil

        {
          login: login,
          prs_reviewed: prs_reviewed,
          prs_authored: authored,
          ratio: ratio
        }
      end

      # Sort by ratio descending, with nil ratios at the end
      sorted = stats.sort_by { |s| s[:ratio] ? -s[:ratio] : 999_999 }

      {
        stats: sorted,
        total_people: all_logins.size,
        high_ratio_count: sorted.count { |s| s[:ratio] && s[:ratio] > 150 && (reviewed_counts[s[:login]] || 0) >= 5 },
        low_ratio_count: sorted.count { |s| s[:ratio] && s[:ratio] < 50 && (author_counts[s[:login]] || 0) >= 5 }
      }
    end
  end
end
