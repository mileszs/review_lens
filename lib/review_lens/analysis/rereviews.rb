# frozen_string_literal: true

module ReviewLens
  module Analysis
    # How reviewers come back to pull requests they held.
    #
    # A reviewer requests changes, or comments without approving. The author
    # pushes. Somebody is now waiting on that reviewer. This measures two
    # different things about that wait:
    #
    #   speed  -- business hours from the author's push to the reviewer's next
    #             review. The clock starts at the push, not at the original
    #             review, so a reviewer is never charged for the days an author
    #             spent making changes.
    #   return rate -- how often they came back at all.
    #
    # Both matter, and a good median can hide a poor rate: returning quickly
    # four times out of ten is not the same as returning quickly.
    #
    # Not returning is not automatically a failure. Someone else may have
    # approved, or the comment may never have been blocking. Reports should say
    # so rather than implying every unreturned thread was dropped.
    class Rereviews
      def initialize(business_hours: Calculators::BusinessHours.new)
        @business_hours = business_hours
      end

      # @param rows [Array<Hash>] {reviewer_login:, pr_number:, pushed_at:, returned_at:}
      # @return [Hash, nil]
      def call(rows)
        return nil if rows.nil? || rows.empty?

        summarize(rows, rows.select { |row| row[:returned_at] })
      end

      private

      def summarize(rows, returned)
        {
          total_waits: rows.length,
          total_returned: returned.length,
          overall_return_rate: percent(returned.length, rows.length),
          overall_median_hours: median_hours(returned),
          reviewer_stats: per_reviewer(rows)
        }
      end

      def per_reviewer(rows)
        stats = rows.group_by { |row| row[:reviewer_login] }
                    .map { |login, events| reviewer_row(login, events) }
        stats.sort_by { |row| -row[:waits] }
      end

      def median_hours(returned)
        Calculators::Median.call(returned.map { |row| elapsed(row) })&.round(1)
      end

      def reviewer_row(login, events)
        returned = events.select { |event| event[:returned_at] }

        {
          reviewer_login: login,
          waits: events.length,
          returned: returned.length,
          return_rate: percent(returned.length, events.length),
          median_hours: median_hours(returned)
        }
      end

      def elapsed(event)
        @business_hours.between(parse(event[:pushed_at]), parse(event[:returned_at]))
      end

      def parse(value)
        value.is_a?(Time) ? value : Time.parse(value.to_s)
      end

      def percent(part, total)
        total.positive? ? (part.to_f / total * 100).round(1) : 0
      end
    end
  end
end
