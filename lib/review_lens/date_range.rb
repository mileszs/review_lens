# frozen_string_literal: true

require 'tzinfo'

module ReviewLens
  # Resolves the reporting window. Defaults to a rolling N-day period ending now.
  module DateRange
    module_function

    # @return [Array(Time, Time)] UTC start and end
    def rolling(days:, timezone: 'America/New_York', start_hour: 8)
      tz = TZInfo::Timezone.get(timezone)
      now = tz.now
      start_date = now.to_date - days
      period_start = tz.local_to_utc(
        tz.local_time(start_date.year, start_date.month, start_date.day, start_hour, 0, 0)
      )
      [period_start, now.utc]
    end

    # Explicit window; accepts Date/Time/parseable String.
    def between(since:, until_time: nil, timezone: 'America/New_York')
      tz = TZInfo::Timezone.get(timezone)
      [to_utc(since, tz), until_time ? to_utc(until_time, tz) : tz.now.utc]
    end

    def to_utc(value, zone)
      case value
      when Time then value.utc
      when Date then zone.local_to_utc(zone.local_time(value.year, value.month, value.day, 0, 0, 0))
      else
        parsed = Date.parse(value.to_s)
        zone.local_to_utc(zone.local_time(parsed.year, parsed.month, parsed.day, 0, 0, 0))
      end
    end
  end
end
