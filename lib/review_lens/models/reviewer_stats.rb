# frozen_string_literal: true

module ReviewLens
  module Models
    # Represents review statistics for a single reviewer
    class ReviewerStats
      attr_reader :reviewer_login, :approved_count, :changes_requested_count, :commented_count,
                  :minimal_count, :brief_count, :substantive_count, :prs_authored

      # Default review depth thresholds (character count). Overridable via
      # Configuration -- they encode an opinion about what "substantive" means.
      MINIMAL_THRESHOLD = 10
      SUBSTANTIVE_THRESHOLD = 100

      def initialize(reviewer_login:, approved_count: 0, changes_requested_count: 0, commented_count: 0,
                     minimal_count: 0, brief_count: 0, substantive_count: 0, prs_authored: 0)
        @reviewer_login = reviewer_login
        @approved_count = approved_count
        @changes_requested_count = changes_requested_count
        @commented_count = commented_count
        @minimal_count = minimal_count
        @brief_count = brief_count
        @substantive_count = substantive_count
        @prs_authored = prs_authored
      end

      # Categorize a review body by depth.
      def self.categorize_depth(body, minimal: MINIMAL_THRESHOLD, substantive: SUBSTANTIVE_THRESHOLD)
        length = (body || '').strip.length
        if length < minimal
          :minimal
        elsif length < substantive
          :brief
        else
          :substantive
        end
      end

      # Returns a copy with the given fields replaced. The object is immutable,
      # so aggregation builds new instances rather than mutating.
      def with(**changes)
        self.class.new(**to_h, **changes)
      end

      def to_h
        {
          reviewer_login: reviewer_login,
          approved_count: approved_count,
          changes_requested_count: changes_requested_count,
          commented_count: commented_count,
          minimal_count: minimal_count,
          brief_count: brief_count,
          substantive_count: substantive_count,
          prs_authored: prs_authored
        }
      end

      def total_reviews
        approved_count + changes_requested_count + commented_count
      end

      def empty?
        total_reviews.zero?
      end

      # Percentage of reviews that were approvals (excluding COMMENTED-only)
      def approval_rate
        actionable = approved_count + changes_requested_count
        return nil if actionable.zero?

        (approved_count.to_f / actionable * 100).round(1)
      end

      # Percentage of reviews that requested changes (excluding COMMENTED-only)
      def change_request_rate
        actionable = approved_count + changes_requested_count
        return nil if actionable.zero?

        (changes_requested_count.to_f / actionable * 100).round(1)
      end

      # Flag for potential rubber-stamping (>95% approval rate with enough data)
      def high_approval_rate?
        rate = approval_rate
        return false if rate.nil?

        actionable = approved_count + changes_requested_count
        actionable >= 5 && rate >= 95.0
      end

      # Total reviews with depth data
      def total_with_depth
        minimal_count + brief_count + substantive_count
      end

      # Percentage of reviews that are substantive (>100 chars)
      def depth_score
        total = total_with_depth
        return nil if total.zero?

        (substantive_count.to_f / total * 100).round(1)
      end

      # Flag for shallow reviews (>50% minimal with enough data)
      def shallow_reviewer?
        total = total_with_depth
        return false if total < 5

        (minimal_count.to_f / total * 100) > 50
      end

      # Ratio of reviews given to PRs authored (e.g., 150% = reviews 1.5x as many PRs as they author)
      def review_author_ratio
        return nil if prs_authored.zero?

        (total_reviews.to_f / prs_authored * 100).round(0).to_i
      end

      # Flag for potentially hogging review opportunities (>150% ratio with enough data)
      def high_review_ratio?
        ratio = review_author_ratio
        return false if ratio.nil?

        total_reviews >= 5 && ratio > 150
      end

      # Flag for potentially not contributing enough reviews (<50% ratio with enough data)
      def low_review_ratio?
        ratio = review_author_ratio
        return false if ratio.nil?

        prs_authored >= 5 && ratio < 50
      end
    end
  end
end
