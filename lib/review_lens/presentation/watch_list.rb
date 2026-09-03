# frozen_string_literal: true

module ReviewLens
  module Presentation
    # Derives "Things to watch" callouts from reviewer metrics.
    # Produces an array of { severity:, title:, body:, refs: [] } hashes.
    #
    # Callout patterns:
    # - high: Re-review delay (delta > 5h, n >= 5)
    # - medium: Rubber-stamp cluster (>= 3 reviewers with >95% approval, <15% depth, 5+ actionable)
    # - medium: Bus factor (always shown; high severity if <= 3)
    # - low: Authors not reviewing back (non-bot with authored >= 5, ratio < 25%)
    # - low: Changes-req. follow-through (<75% effectiveness, >= 2 changes requested)
    class WatchList
      # Thresholds as named constants for easy tuning
      REREVIEW_DELAY_THRESHOLD = 5       # hours
      REREVIEW_DELAY_MIN_N = 5           # minimum sample size
      RUBBER_STAMP_CLUSTER_MIN = 3       # minimum reviewers to trigger
      RUBBER_STAMP_APPROVAL_THRESHOLD = 95 # percent
      RUBBER_STAMP_DEPTH_THRESHOLD = 15  # percent
      RUBBER_STAMP_MIN_ACTIONABLE = 5    # minimum actionable reviews
      BUS_FACTOR_HIGH_SEVERITY = 3       # threshold for high vs medium
      LOW_RATIO_THRESHOLD = 25           # percent
      LOW_RATIO_MIN_AUTHORED = 5         # minimum PRs authored
      CHANGES_REQ_RATE_THRESHOLD = 75    # percent
      CHANGES_REQ_MIN_COUNT = 2          # minimum changes requested

      class << self
        # Derive all callouts from metrics data
        # @param meta [Hash] Report metadata (bus_factor, gini, pr_distribution, etc.)
        # @param reviewers [Array<Hash>] Reviewer data hashes
        # @return [Array<Hash>] Callout hashes with :severity, :title, :body, :refs
        def derive(meta:, reviewers:)
          callouts = []

          callouts.concat(rereview_delay_callouts(reviewers))
          callouts << rubber_stamp_callout(reviewers) if rubber_stamp_callout(reviewers)
          callouts << bus_factor_callout(meta) if bus_factor_callout(meta)
          callouts << low_ratio_callout(reviewers) if low_ratio_callout(reviewers)
          callouts.concat(changes_req_followthrough_callouts(reviewers, meta))

          callouts
        end

        private

        # Generate callouts for reviewers with significant re-review delays
        def rereview_delay_callouts(reviewers)
          reviewers.filter_map do |r|
            next unless r[:response_delta] && r[:response_n]
            next unless r[:response_delta] > REREVIEW_DELAY_THRESHOLD && r[:response_n] >= REREVIEW_DELAY_MIN_N

            {
              severity: :high,
              title: "#{r[:name]} re-review delay",
              body: "Initial response is #{format_hours(r[:response_initial])} but re-reviews jump to " \
                    "#{format_hours(r[:response_re_review])} — a #{format_delta(r[:response_delta])} delta. " \
                    'Re-requested PRs are sitting much longer than fresh ones.',
              refs: [r[:name]]
            }
          end
        end

        # Generate callout for rubber-stamp cluster
        def rubber_stamp_callout(reviewers)
          rubber_stampers = reviewers.select do |r|
            next false if r[:bot]
            next false unless r[:approval_pct] && r[:actionable]
            next false if r[:actionable] < RUBBER_STAMP_MIN_ACTIONABLE

            r[:approval_pct] > RUBBER_STAMP_APPROVAL_THRESHOLD &&
              (r[:depth_pct].nil? || r[:depth_pct] < RUBBER_STAMP_DEPTH_THRESHOLD)
          end

          return nil if rubber_stampers.length < RUBBER_STAMP_CLUSTER_MIN

          names = rubber_stampers.map { |r| r[:name] }
          sample = names.first(4).join(', ')
          sample += ', ...' if names.length > 4

          {
            severity: :medium,
            title: 'Rubber-stamp cluster',
            body: "#{names.length} reviewers have >95% approval rate AND <15% substantive depth " \
                  "on 5+ reviews — including #{sample}. High volume, low pushback, brief comments.",
            refs: names
          }
        end

        # Generate bus factor callout (always shown)
        def bus_factor_callout(meta)
          return nil unless meta[:bus_factor]

          severity = meta[:bus_factor] <= BUS_FACTOR_HIGH_SEVERITY ? :high : :medium

          {
            severity: severity,
            title: "Bus factor of #{meta[:bus_factor]}",
            body: "#{meta[:bus_factor]} reviewers cover 50% of all reviews; " \
                  "top 3 alone cover #{meta[:top_3_share]&.round(1) || '?'}%. " \
                  "Gini #{meta[:gini]&.round(2) || '?'} indicates #{gini_description(meta[:gini])}.",
            refs: []
          }
        end

        # Generate callout for authors not reviewing back
        def low_ratio_callout(reviewers)
          low_contributors = reviewers.select do |r|
            next false if r[:bot]
            next false unless r[:ratio] && r[:prs_authored]
            next false if r[:prs_authored] < LOW_RATIO_MIN_AUTHORED

            r[:ratio] < LOW_RATIO_THRESHOLD
          end

          return nil if low_contributors.empty?

          names = low_contributors.map { |r| r[:name] }
          examples = low_contributors.first(3).map do |r|
            "#{r[:name]} (#{r[:prs_authored]} PRs authored, #{r[:prs_reviewed]} reviewed)"
          end

          {
            severity: :low,
            title: 'Authors not reviewing back',
            body: "#{examples.join(', ')} author significantly more than they review.",
            refs: names
          }
        end

        # Generate callouts for reviewers with low changes-requested follow-through
        def changes_req_followthrough_callouts(reviewers, meta)
          overall_rate = meta[:review_effectiveness_overall] || 100

          reviewers.filter_map do |r|
            next if r[:bot]
            next unless r[:chg_req_rate] && r[:changes_requested]
            next if r[:changes_requested] < CHANGES_REQ_MIN_COUNT
            next unless r[:chg_req_rate] < CHANGES_REQ_RATE_THRESHOLD

            {
              severity: :low,
              title: "#{r[:name]} changes-requested follow-through",
              body: "Only #{r[:chg_req_rate].round(0)}% of their CHANGES_REQUESTED reviews were " \
                    "followed by code commits — well below the #{overall_rate.round(1)}% team average.",
              refs: [r[:name]]
            }
          end
        end

        def format_hours(hours)
          return '?' if hours.nil?

          "#{hours.round(1)}h"
        end

        def format_delta(delta)
          return '?' if delta.nil?

          sign = delta >= 0 ? '+' : ''
          "#{sign}#{delta.round(1)}h"
        end

        def gini_description(gini)
          return 'unknown concentration' if gini.nil?

          if gini < 0.3
            'low concentration'
          elsif gini < 0.5
            'moderate concentration'
          else
            'high concentration'
          end
        end
      end
    end
  end
end
