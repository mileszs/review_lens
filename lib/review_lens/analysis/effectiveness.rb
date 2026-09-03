# frozen_string_literal: true

module ReviewLens
  module Analysis
    # How often a "changes requested" review was followed by more commits.
    #
    # A proxy for whether review feedback actually landed. It is only a proxy:
    # an author may push nothing because the reviewer was wrong, or because the
    # discussion resolved in the author's favour. Read it as a conversation
    # starter, not a verdict.
    module Effectiveness
      module_function

      # @param rows [Array<Hash>] {reviewer_login:, had_subsequent_commit:}
      # @return [Hash, nil]
      def call(rows)
        return nil if rows.nil? || rows.empty?

        total = rows.length
        effective = rows.count { |r| r[:had_subsequent_commit] }

        {
          total_changes_requested: total,
          total_effective: effective,
          overall_effectiveness_rate: rate(effective, total),
          reviewer_stats: per_reviewer(rows)
        }
      end

      def per_reviewer(rows)
        stats = rows.group_by { |r| r[:reviewer_login] }.map do |login, reviews|
          effective = reviews.count { |r| r[:had_subsequent_commit] }
          {
            reviewer_login: login,
            changes_requested_count: reviews.length,
            effective_count: effective,
            effectiveness_rate: rate(effective, reviews.length)
          }
        end
        stats.sort_by { |row| -row[:effectiveness_rate] }
      end

      def rate(part, total)
        total.positive? ? (part.to_f / total * 100).round(1) : 0
      end
    end
  end
end
