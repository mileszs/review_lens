# frozen_string_literal: true

module ReviewLens
  module Analysis
    # How long reviewers take to respond to a review request, in business hours.
    #
    # Initial requests and re-review requests are measured separately: waiting
    # on a second look after changes is a different experience from waiting on
    # the first, and mixing them hides that.
    class ResponseTimes
      def initialize(business_hours: Calculators::BusinessHours.new)
        @business_hours = business_hours
      end

      # @param rows [Array<Hash>] {requested_reviewer:, pr_number:, requested_at:,
      #   first_review_at:, is_rerequest:}
      # @return [Hash, nil]
      def call(rows)
        return nil if rows.nil? || rows.empty?

        initial = for_group(rows.reject { |r| r[:is_rerequest] })
        return nil unless initial

        combine(rows, initial, for_group(rows.select { |r| r[:is_rerequest] }))
      end

      private

      def combine(rows, initial, rereview)
        {
          overall_median_hours: initial[:overall_median_hours],
          total_requests: rows.length,
          responded_count: initial[:responded_count] + (rereview&.dig(:responded_count) || 0),
          reviewer_stats: initial[:reviewer_stats],
          rereview_metrics: rereview,
          comparison_stats: comparison(initial, rereview)
        }
      end

      def for_group(rows)
        return nil if rows.empty?

        responded = response_times(rows).select(&:responded?)
        return nil if responded.empty?

        all_hours = responded.filter_map(&:response_hours)
        return nil if all_hours.empty?

        {
          overall_median_hours: Calculators::Median.call(all_hours).round(1),
          total_requests: rows.length,
          responded_count: responded.length,
          reviewer_stats: per_reviewer(responded)
        }
      end

      def response_times(rows)
        rows.map do |row|
          Models::ReviewerResponseTime.new(
            reviewer_login: row[:requested_reviewer],
            pr_number: row[:pr_number],
            requested_at: row[:requested_at],
            first_review_at: row[:first_review_at],
            business_hours: @business_hours
          )
        end
      end

      def per_reviewer(responded)
        stats = responded.group_by(&:reviewer_login).filter_map do |login, times|
          hours = times.filter_map(&:response_hours)
          next if hours.empty?

          {
            reviewer_login: login,
            median_hours: Calculators::Median.call(hours).round(1),
            review_count: hours.length
          }
        end
        stats.sort_by { |row| row[:median_hours] }
      end

      # Reviewers who have both initial and re-review data, sorted by the
      # biggest slowdown on second look.
      def comparison(initial, rereview)
        return nil unless rereview

        first = medians_by_login(initial)
        second = medians_by_login(rereview)
        common = first.keys & second.keys
        return nil if common.empty?

        deltas = common.map { |login| delta_row(login, first[login], second[login]) }
        deltas.sort_by { |row| -row[:delta_hours] }
      end

      def medians_by_login(metrics)
        metrics[:reviewer_stats].to_h { |stat| [stat[:reviewer_login], stat[:median_hours]] }
      end

      def delta_row(login, initial_hours, rereview_hours)
        {
          reviewer_login: login,
          initial_hours: initial_hours,
          rereview_hours: rereview_hours,
          delta_hours: (rereview_hours - initial_hours).round(1)
        }
      end
    end
  end
end
