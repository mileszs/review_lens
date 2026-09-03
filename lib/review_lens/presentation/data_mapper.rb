# frozen_string_literal: true

module ReviewLens
  module Presentation
    # Maps Ruby metrics data to the format expected by the HTML template.
    # Transforms Analyzer output into structures matching data.js.
    class DataMapper
      def initialize(metrics:, week_start:, week_end:, config:)
        @metrics = metrics
        @week_start = week_start
        @week_end = week_end
        @config = config
      end

      # Map to REPORT_META structure
      # @return [Hash]
      def report_meta
        review_rounds = @metrics[:review_rounds] || {}
        distribution = @metrics[:distribution] || {}
        cross_squad = @metrics[:cross_squad] || {}
        response_times = @metrics[:response_times] || {}
        effectiveness = @metrics[:effectiveness] || {}

        {
          repo: @config.repo,
          period_start: format_date(@week_start),
          period_end: format_date(@week_end),
          total_reviewers: @metrics[:total_reviewers] || 0,
          total_reviews: @metrics[:total_reviews] || 0,
          total_prs: review_rounds[:total_prs] || 0,
          median_reviews_per_pr: review_rounds[:median],
          mean_reviews_per_pr: review_rounds[:mean],
          max_reviews_on_pr: review_rounds[:max],
          bus_factor: distribution[:bus_factor],
          gini: distribution[:gini],
          top_share: distribution[:top_reviewer_share],
          top_3_share: distribution[:top_3_share],
          health: format_health(distribution[:health]),
          pr_distribution: map_pr_distribution(review_rounds[:distribution]),
          cross_squad: {
            same: cross_squad[:same_squad_reviews] || 0,
            cross: cross_squad[:cross_squad_reviews] || 0,
            external: cross_squad[:external_reviews] || 0,
            rate: cross_squad[:cross_squad_rate] || 0
          },
          response_initial_median: response_times[:overall_median_hours],
          response_requests: response_times[:total_requests] || 0,
          response_completed: response_times[:responded_count] || 0,
          review_effectiveness_overall: effectiveness[:overall_effectiveness_rate],
          changes_requested_total: effectiveness[:total_changes_requested] || 0,
          changes_requested_followed_by_commit: effectiveness[:total_effective] || 0
        }
      end

      # Map to REVIEWERS array structure
      # @return [Array<Hash>]
      def reviewers
        reviewer_stats = @metrics[:reviewer_stats] || []
        total_reviews = @metrics[:total_reviews] || 0

        # Build lookup tables for supplementary data
        cross_squad_by_login = build_cross_squad_lookup
        response_by_login = build_response_lookup
        rereview_by_login = build_rereview_lookup
        effectiveness_by_login = build_effectiveness_lookup
        ratio_by_login = build_ratio_lookup

        reviewer_stats.map do |stats|
          login = stats.reviewer_login
          map_reviewer(stats, total_reviews, cross_squad_by_login[login],
                       response_by_login[login], rereview_by_login[login],
                       effectiveness_by_login[login], ratio_by_login[login])
        end
      end

      private

      def map_reviewer(stats, total_reviews, cross_squad, response, rereview, effectiveness, ratio_data)
        login = stats.reviewer_login
        total = stats.total_reviews
        actionable = stats.approved_count + stats.changes_requested_count

        reviewer = {
          name: login,
          bot: bot?(login),
          approved: stats.approved_count,
          changes_requested: stats.changes_requested_count,
          commented: stats.commented_count,
          total: total,
          share_pct: total_reviews.positive? ? (total.to_f / total_reviews * 100).round(1) : 0,
          actionable: actionable,
          approval_pct: stats.approval_rate,
          changes_req_pct: stats.change_request_rate,
          minimal: stats.minimal_count,
          brief: stats.brief_count,
          substantive: stats.substantive_count,
          depth_pct: stats.depth_score,
          prs_reviewed: ratio_data&.dig(:prs_reviewed) || 0,
          prs_authored: stats.prs_authored,
          ratio: ratio_data&.dig(:ratio)
        }

        # Merge cross-squad data
        if cross_squad
          reviewer[:cross_squad_same] = cross_squad[:same_squad]
          reviewer[:cross_squad_cross] = cross_squad[:cross_squad]
          reviewer[:cross_squad_rate] = cross_squad[:cross_squad_rate]
        end

        # Merge response time data
        if response
          reviewer[:response_initial] = response[:median_hours]
          reviewer[:response_n] = response[:review_count]
        end

        # Merge re-review data
        if rereview
          reviewer[:response_re_review] = rereview[:median_hours]
          reviewer[:response_delta] = rereview[:delta_hours] if rereview[:delta_hours]
        end

        # Merge effectiveness data
        if effectiveness
          reviewer[:chg_req_effective] = effectiveness[:effective_count]
          reviewer[:chg_req_rate] = effectiveness[:effectiveness_rate]
        end

        add_flags(reviewer)
        reviewer
      end

      # Evaluative labels ("rubber stamp", "under contributing") are opt-in and
      # only ever reach the team report -- never an individual's own report.
      # Off by default: a label attached to a name invites a judgement the data
      # cannot support on its own.
      def add_flags(reviewer)
        unless @config.show_flags
          reviewer[:flagged] = false
          reviewer[:badges] = []
          reviewer[:ratio_flag] = nil
          return reviewer
        end

        reviewer[:flagged] = Calculators::ReviewerFlags.any_flag?(reviewer)
        reviewer[:badges] = Calculators::ReviewerFlags.badges(reviewer)
        reviewer[:ratio_flag] = Calculators::ReviewerFlags.ratio_flag(
          ratio: reviewer[:ratio],
          prs_reviewed: reviewer[:prs_reviewed],
          prs_authored: reviewer[:prs_authored]
        )
        reviewer
      end

      def bot?(login)
        @config.bot?(login)
      end

      def format_date(time)
        time.strftime('%b %d, %Y')
      end

      def format_health(health)
        return 'Unknown' if health.nil?

        case health.to_sym
        when :good
          'Healthy distribution'
        when :moderate
          'Moderate — Some concentration'
        when :concentrated
          'Concentrated — High risk'
        else
          health.to_s.capitalize
        end
      end

      def map_pr_distribution(distribution)
        return [] unless distribution

        [
          { bucket: '1 review', prs: distribution[1] || 0, pct: 0 },
          { bucket: '2 reviews', prs: distribution[2] || 0, pct: 0 },
          { bucket: '3+ reviews', prs: distribution['3+'] || 0, pct: 0 }
        ].tap do |dist|
          total = dist.sum { |d| d[:prs] }
          dist.each { |d| d[:pct] = total.positive? ? (d[:prs].to_f / total * 100).round(1) : 0 }
        end
      end

      def build_cross_squad_lookup
        cross_squad = @metrics[:cross_squad] || {}
        reviewer_stats = cross_squad[:reviewer_stats] || []
        reviewer_stats.to_h { |r| [r[:reviewer_login], r] }
      end

      def build_response_lookup
        response_times = @metrics[:response_times] || {}
        reviewer_stats = response_times[:reviewer_stats] || []
        reviewer_stats.to_h { |r| [r[:reviewer_login], r] }
      end

      def build_rereview_lookup
        response_times = @metrics[:response_times] || {}
        comparison_stats = response_times[:comparison_stats] || []
        rereview_stats = response_times.dig(:rereview_metrics, :reviewer_stats) || []

        # Build lookup from comparison stats (has delta)
        comparison_by_login = comparison_stats.to_h { |r| [r[:reviewer_login], r] }

        # Build lookup from re-review stats (has median hours)
        rereview_by_login = rereview_stats.to_h { |r| [r[:reviewer_login], r] }

        # Merge them
        all_logins = (comparison_by_login.keys + rereview_by_login.keys).uniq
        all_logins.to_h do |login|
          data = {}
          data[:median_hours] = rereview_by_login.dig(login, :median_hours)
          data[:delta_hours] = comparison_by_login.dig(login, :delta_hours)
          [login, data]
        end
      end

      def build_effectiveness_lookup
        effectiveness = @metrics[:effectiveness] || {}
        reviewer_stats = effectiveness[:reviewer_stats] || []
        reviewer_stats.to_h { |r| [r[:reviewer_login], r] }
      end

      def build_ratio_lookup
        ratio = @metrics[:review_author_ratio] || {}
        stats = ratio[:stats] || []
        stats.to_h { |r| [r[:login], r] }
      end
    end
  end
end
