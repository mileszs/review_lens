# frozen_string_literal: true

module ReviewLens
  module Calculators
    # Calculates review distribution metrics to identify concentration risk
    class ReviewDistribution
      attr_reader :review_counts, :total_reviews, :reviewer_count

      def initialize(review_counts)
        @review_counts = review_counts.sort.reverse # Descending order
        @total_reviews = review_counts.sum
        @reviewer_count = review_counts.size
      end

      # Gini coefficient: 0 = perfect equality, 1 = total inequality
      # Higher values mean reviews are concentrated in fewer people
      def gini_coefficient
        return 0 if @reviewer_count <= 1 || @total_reviews.zero?

        sorted = @review_counts.sort
        n = sorted.length

        # Gini formula: (2 * sum of (i * x_i)) / (n * sum of x_i) - (n + 1) / n
        cumulative_sum = sorted.each_with_index.sum { |count, i| (i + 1) * count }
        ((2.0 * cumulative_sum) / (n * @total_reviews)) - ((n + 1.0) / n)
      end

      # Bus factor: minimum reviewers needed to cover 50% of reviews
      # Lower values = higher risk (knowledge concentrated in few people)
      def bus_factor
        return 0 if @total_reviews.zero?

        threshold = @total_reviews * 0.5
        cumulative = 0

        @review_counts.each_with_index do |count, i|
          cumulative += count
          return i + 1 if cumulative >= threshold
        end

        @reviewer_count
      end

      # Percentage of reviews done by the top reviewer
      def top_reviewer_share
        return 0 if @total_reviews.zero?

        (@review_counts.first.to_f / @total_reviews * 100).round(1)
      end

      # Percentage of reviews done by top N reviewers
      def top_n_share(count)
        return 0 if @total_reviews.zero?

        top_n_total = @review_counts.first(count).sum
        (top_n_total.to_f / @total_reviews * 100).round(1)
      end

      # Health assessment based on metrics
      def health_rating
        gini = gini_coefficient
        bf = bus_factor

        if gini < 0.3 && bf >= 3
          :good
        elsif gini < 0.5 && bf >= 2
          :moderate
        else
          :concentrated
        end
      end
    end
  end
end
