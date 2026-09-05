# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::BusinessHours do
  subject(:calc) { described_class.new }

  # Default window is 08:00-18:00 America/New_York, weekdays.
  # 2026-06-01 is a Monday; June is EDT (UTC-4).
  def et(day, hour, minute = 0)
    Time.new(2026, 6, day, hour, minute, 0, '-04:00').utc
  end

  describe '#between' do
    it 'counts hours inside a single business day' do
      expect(calc.between(et(1, 9), et(1, 12))).to eq(3.0)
    end

    it 'ignores time before the working day starts' do
      expect(calc.between(et(1, 5), et(1, 10))).to eq(2.0)
    end

    it 'ignores time after the working day ends' do
      expect(calc.between(et(1, 17), et(1, 23))).to eq(1.0)
    end

    it 'counts a full working day as the configured span' do
      expect(calc.between(et(1, 0), et(1, 23, 59))).to eq(10.0)
    end

    it 'spans consecutive weekdays' do
      # Mon 16:00 -> Tue 10:00 = 2h Monday + 2h Tuesday
      expect(calc.between(et(1, 16), et(2, 10))).to eq(4.0)
    end

    # The metric this powers exists so that an out-of-hours wait does not look
    # like neglect. A Friday evening request answered Monday morning is fast.
    it 'skips the weekend entirely' do
      friday_evening = et(5, 17, 30)
      monday_morning = et(8, 8, 30)

      expect(calc.between(friday_evening, monday_morning)).to eq(1.0)
    end

    it 'returns zero for a period entirely within a weekend' do
      expect(calc.between(et(6, 9), et(7, 17))).to eq(0.0)
    end

    it 'returns zero when the end is before the start' do
      expect(calc.between(et(1, 15), et(1, 9))).to eq(0.0)
    end

    it 'returns zero for identical times' do
      expect(calc.between(et(1, 10), et(1, 10))).to eq(0.0)
    end

    it 'returns zero when either side is nil' do
      expect(calc.between(nil, et(1, 10))).to eq(0.0)
      expect(calc.between(et(1, 10), nil)).to eq(0.0)
    end

    it 'handles partial hours' do
      expect(calc.between(et(1, 9), et(1, 9, 30))).to eq(0.5)
    end

    it 'accumulates across a whole working week' do
      # Mon 08:00 -> Fri 18:00 = five 10-hour days
      expect(calc.between(et(1, 8), et(5, 18))).to eq(50.0)
    end

    it 'accepts non-UTC inputs' do
      expect(calc.between(Time.new(2026, 6, 1, 9, 0, 0, '-04:00'), Time.new(2026, 6, 1, 12, 0, 0, '-04:00')))
        .to eq(3.0)
    end
  end

  describe 'configurability' do
    it 'honours a custom working window' do
      calc = described_class.new(start_hour: 9, end_hour: 17)

      expect(calc.between(et(1, 0), et(1, 23))).to eq(8.0)
    end

    it 'honours a different timezone' do
      london = described_class.new(timezone: 'Europe/London')
      # 08:00-18:00 BST (UTC+1) on Monday 2026-06-01
      start_time = Time.new(2026, 6, 1, 9, 0, 0, '+01:00')
      end_time = Time.new(2026, 6, 1, 12, 0, 0, '+01:00')

      expect(london.between(start_time, end_time)).to eq(3.0)
    end

    # A distributed team may want every hour of a weekday to count.
    it 'supports a full 24-hour weekday window' do
      calc = described_class.new(start_hour: 0, end_hour: 24)

      expect(calc.between(et(1, 0), et(2, 0))).to eq(24.0)
    end

    it 'still skips weekends with a 24-hour window' do
      calc = described_class.new(start_hour: 0, end_hour: 24)

      expect(calc.between(et(6, 0), et(8, 0))).to eq(0.0)
    end

    it 'rejects hours outside 0..24' do
      expect { described_class.new(start_hour: 8, end_hour: 25) }.to raise_error(ArgumentError, /0\.\.24/)
    end

    it 'rejects a window that ends before it starts' do
      expect { described_class.new(start_hour: 18, end_hour: 8) }
        .to raise_error(ArgumentError, /before/)
    end
  end

  describe 'daylight saving transitions' do
    # US DST began 2026-03-08. The clock jumps 02:00 -> 03:00, which is outside
    # the working window, so a normal working day still measures 10 hours.
    it 'measures a normal day across the spring-forward boundary' do
      monday_after = Time.new(2026, 3, 9, 8, 0, 0, '-04:00')
      monday_end = Time.new(2026, 3, 9, 18, 0, 0, '-04:00')

      expect(calc.between(monday_after, monday_end)).to eq(10.0)
    end

    it 'spans the spring-forward weekend without error' do
      friday = Time.new(2026, 3, 6, 17, 0, 0, '-05:00')
      monday = Time.new(2026, 3, 9, 9, 0, 0, '-04:00')

      expect(calc.between(friday, monday)).to eq(2.0)
    end
  end
end
