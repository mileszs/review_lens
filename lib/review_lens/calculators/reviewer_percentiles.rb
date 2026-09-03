# frozen_string_literal: true

module ReviewLens
  module Calculators
    # Positions one reviewer against the cohort for the individual (private)
    # report. Given the per-reviewer array from DataMapper#reviewers and
    # a focus login, computes, per metric, the team median and the focus
    # reviewer's rank + percentile — plus the sorted (unlabeled) value list so the
    # report can draw an anonymized distribution strip.
    #
    # Bots are excluded from the cohort. The result is direction-agnostic: it
    # reports the team median and the share of the cohort strictly below/above
    # the focus value, so the report can phrase it correctly per metric (e.g.
    # "higher than X%" for depth, "lower than X%" for response time) without this
    # calculator judging which direction is "better".
    class ReviewerPercentiles
      # Comparing someone against a cohort that is only themselves produces a
      # confident-looking "higher than 0% of the team". Below this, say nothing.
      MIN_COHORT = 3

      def initialize(reviewers, focus_login)
        @reviewers = (reviewers || []).reject { |r| r[:bot] }
        @focus_login = focus_login
      end

      # Returns nil when the focus reviewer has no usable value for the metric
      # (missing, non-numeric, or below the minimum sample), otherwise:
      #   { value:, median:, count:, values: [sorted asc], pct_below:, pct_above: }
      def for_metric(key, min_sample_key: nil, min_sample: 0)
        eligible = @reviewers.select { |r| eligible?(r, key, min_sample_key, min_sample) }
        return nil if eligible.length < MIN_COHORT

        focus = eligible.find { |r| r[:name] == @focus_login }
        return nil unless focus

        summarize(eligible.map { |r| r[key].to_f }.sort, focus[key].to_f)
      end

      private

      def summarize(values, value)
        count = values.length
        {
          value: value,
          median: Median.call(values),
          count: count,
          values: values,
          pct_below: percent(values.count { |x| x < value }, count),
          pct_above: percent(values.count { |x| x > value }, count)
        }
      end

      def percent(amount, total)
        (amount.to_f / total * 100).round
      end

      def eligible?(reviewer, key, min_sample_key, min_sample)
        return false unless reviewer[key].is_a?(Numeric)
        return true unless min_sample_key

        (reviewer[min_sample_key] || 0) >= min_sample
      end
    end
  end
end
