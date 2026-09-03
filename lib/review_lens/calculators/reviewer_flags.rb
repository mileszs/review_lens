# frozen_string_literal: true

module ReviewLens
  module Calculators
    # Pure functions for computing reviewer flags and badges.
    # Used by watch list derivation and HTML template rendering.
    #
    # Some flags are already implemented in ReviewerStats model:
    # - high_approval_rate? (rubber-stamp)
    # - shallow_reviewer? (depth)
    # - high_review_ratio? / low_review_ratio? (ratio)
    #
    # This module provides additional flags and aggregation.
    module ReviewerFlags
      MIN_ACTIONABLE = 5
      HIGH_APPROVAL_PCT = 95
      # Thresholds as named constants for easy tuning
      RESPONSE_DELAY_THRESHOLD = 5    # hours
      RESPONSE_DELAY_MIN_N = 5        # minimum sample size
      LOW_EFFECTIVENESS_THRESHOLD = 75 # percent
      LOW_EFFECTIVENESS_MIN_COUNT = 2  # minimum changes requested

      module_function

      # Flag for re-review response delay (initial vs re-review delta)
      # @param delta [Numeric, nil] Hours difference between initial and re-review response
      # @param sample_size [Integer, nil] Number of re-review data points
      # @return [Boolean]
      def response_delay_flag?(delta:, sample_size:)
        return false if delta.nil? || sample_size.nil?

        delta > RESPONSE_DELAY_THRESHOLD && sample_size >= RESPONSE_DELAY_MIN_N
      end

      # Flag for low changes-requested effectiveness
      # @param rate [Numeric, nil] Percentage of CHANGES_REQUESTED followed by commits
      # @param count [Integer, nil] Number of CHANGES_REQUESTED reviews
      # @return [Boolean]
      def low_effectiveness_flag?(rate:, count:)
        return false if rate.nil? || count.nil?

        rate < LOW_EFFECTIVENESS_THRESHOLD && count >= LOW_EFFECTIVENESS_MIN_COUNT
      end

      # Compute badge symbols for a reviewer
      # @param reviewer [Hash] Reviewer data with approval_pct, depth_pct, actionable, etc.
      # @return [Array<Symbol>] List of badge symbols (:rubber_stamp, :load_bearing, :under_contributing)
      def badges(reviewer)
        badges = []

        # Rubber-stamp: >95% approval AND actionable >= 5
        if reviewer[:approval_pct] && reviewer[:actionable] &&
           reviewer[:actionable] >= MIN_ACTIONABLE && reviewer[:approval_pct] > HIGH_APPROVAL_PCT
          badges << :rubber_stamp
        end

        # Load-bearing: ratio > 150% AND prs_reviewed >= 5
        if reviewer[:ratio] && reviewer[:prs_reviewed] && reviewer[:prs_reviewed] >= 5 && (reviewer[:ratio] > 150)
          badges << :load_bearing
        end

        # Under-contributing: ratio < 50% AND prs_authored >= 5
        if reviewer[:ratio] && reviewer[:prs_authored] && reviewer[:prs_authored] >= 5 && (reviewer[:ratio] < 50)
          badges << :under_contributing
        end

        badges
      end

      # Check if a reviewer has any flag that warrants attention
      # @param reviewer [Hash] Reviewer data hash
      # @return [Boolean]
      def any_flag?(reviewer)
        return true if reviewer[:approval_pct] && reviewer[:approval_pct] > 95 && (reviewer[:actionable] || 0) >= 5
        return true if response_delay_flag?(delta: reviewer[:response_delta], sample_size: reviewer[:response_n])
        return true if low_effectiveness_flag?(rate: reviewer[:chg_req_rate], count: reviewer[:changes_requested])

        if reviewer[:ratio]
          return true if reviewer[:ratio] > 150 && (reviewer[:prs_reviewed] || 0) >= 5
          return true if reviewer[:ratio] < 50 && (reviewer[:prs_authored] || 0) >= 5
        end

        false
      end

      # Determine ratio flag type
      # @param ratio [Numeric, nil] Review/author ratio percentage
      # @param prs_reviewed [Integer] Number of unique PRs reviewed
      # @param prs_authored [Integer] Number of PRs authored
      # @return [Symbol, nil] :high, :low, or nil
      def ratio_flag(ratio:, prs_reviewed:, prs_authored:)
        return nil if ratio.nil?
        return :high if ratio > 150 && prs_reviewed >= 5
        return :low if ratio < 50 && prs_authored >= 5

        nil
      end
    end
  end
end
