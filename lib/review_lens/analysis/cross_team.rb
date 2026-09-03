# frozen_string_literal: true

module ReviewLens
  module Analysis
    # How much reviewing crosses team boundaries.
    #
    # Entirely optional: with no team map configured this returns nil and the
    # section is omitted from reports rather than rendered as zeroes.
    #
    # The output keys keep the `cross_squad` naming used by the report
    # templates and data mapper.
    class CrossTeam
      def initialize(config)
        @config = config
      end

      # @param review_pairs [Array<Hash>] {reviewer_login:, author_login:, count:}
      # @return [Hash, nil]
      def call(review_pairs)
        return nil if review_pairs.nil? || review_pairs.empty?
        return nil unless @config.teams?

        totals = { same: 0, cross: 0, external: 0 }
        per_reviewer = Hash.new { |h, k| h[k] = { same: 0, cross: 0, external: 0 } }

        review_pairs.each { |pair| tally(pair, totals, per_reviewer) }
        build(totals, per_reviewer)
      end

      private

      def tally(pair, totals, per_reviewer)
        bucket = classify(pair[:reviewer_login], pair[:author_login])
        count = pair[:count].to_i
        totals[bucket] += count
        per_reviewer[pair[:reviewer_login]][bucket] += count
      end

      # A review is external when either side isn't on a known team -- we can't
      # say whether it crossed a boundary, so it's excluded from the rate.
      def classify(reviewer_login, author_login)
        reviewer_team = @config.team_for(reviewer_login)
        author_team = @config.team_for(author_login)
        return :external if reviewer_team.nil? || author_team.nil?

        reviewer_team == author_team ? :same : :cross
      end

      def build(totals, per_reviewer)
        {
          same_squad_reviews: totals[:same],
          cross_squad_reviews: totals[:cross],
          external_reviews: totals[:external],
          cross_squad_rate: rate(totals[:cross], totals[:same] + totals[:cross]),
          reviewer_stats: reviewer_stats(per_reviewer)
        }
      end

      def reviewer_stats(per_reviewer)
        rows = per_reviewer.map do |login, counts|
          {
            reviewer_login: login,
            same_squad: counts[:same],
            cross_squad: counts[:cross],
            external: counts[:external],
            cross_squad_rate: rate(counts[:cross], counts[:same] + counts[:cross])
          }
        end
        rows.sort_by { |row| -row[:cross_squad] }
      end

      def rate(part, total)
        total.positive? ? (part.to_f / total * 100).round(1) : 0
      end
    end
  end
end
