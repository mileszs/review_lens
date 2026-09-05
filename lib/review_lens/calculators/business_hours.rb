# frozen_string_literal: true

require 'tzinfo'
require 'date'

module ReviewLens
  module Calculators
    # Elapsed time between two instants, counting only working hours on
    # weekdays in a configured timezone.
    #
    # Used for response-time metrics so that a review request sent at 4:55pm
    # Friday and answered 9:05am Monday reads as ~10 minutes, not 64 hours.
    #
    # Note: weekends only. There is no holiday calendar, so a request spanning
    # a public holiday will overstate elapsed working time.
    class BusinessHours
      SECONDS_PER_HOUR = 3600.0

      attr_reader :timezone, :start_hour, :end_hour

      # end_hour 24 means midnight at the end of the day, so a team spread
      # across timezones can count every hour of a weekday.
      def initialize(timezone: 'America/New_York', start_hour: 8, end_hour: 18)
        raise ArgumentError, 'start_hour must be before end_hour' unless start_hour < end_hour
        raise ArgumentError, 'hours must be within 0..24' unless start_hour >= 0 && end_hour <= 24

        @tz = TZInfo::Timezone.get(timezone)
        @timezone = timezone
        @start_hour = start_hour
        @end_hour = end_hour
      end

      # @return [Float] business hours between the two instants (0.0 if either
      #   is nil, or if they are out of order)
      def between(start_time, end_time)
        return 0.0 if start_time.nil? || end_time.nil?

        from = start_time.getutc
        to = end_time.getutc
        return 0.0 if to <= from

        each_date(from, to).sum { |date| overlap_on(date, from, to) }
      end

      private

      def each_date(from, to)
        (@tz.to_local(from).to_date..@tz.to_local(to).to_date).reject { |d| weekend?(d) }
      end

      # Hours of [from, to] that fall inside this date's business window.
      def overlap_on(date, from, to)
        window_start = utc_at(date, @start_hour)
        window_end = utc_at(date, @end_hour)
        return 0.0 unless window_start && window_end

        low = [from, window_start].max
        high = [to, window_end].min
        high > low ? (high - low) / SECONDS_PER_HOUR : 0.0
      end

      def weekend?(date)
        date.saturday? || date.sunday?
      end

      # Convert a local wall-clock hour on a date to UTC, resolving DST
      # ambiguity to the first matching period. Returns nil for a wall-clock
      # time that does not exist on that date (spring-forward gap).
      def utc_at(date, hour)
        day = hour == 24 ? date + 1 : date
        clock = hour == 24 ? 0 : hour
        local = @tz.local_time(day.year, day.month, day.day, clock, 0, 0)
        @tz.local_to_utc(local, &:first)
      rescue TZInfo::PeriodNotFound
        nil
      end
    end
  end
end
