# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Analysis::Rereviews do
  subject(:analysis) { described_class.new }

  # Monday 2026-06-01, EDT. Default working window is 08:00-18:00 ET.
  def et(day, hour)
    Time.new(2026, 6, day, hour, 0, 0, '-04:00').utc.iso8601
  end

  def wait(login, pushed:, returned: nil, number: 1)
    { reviewer_login: login, pr_number: number, pushed_at: pushed, returned_at: returned }
  end

  describe '#call' do
    subject(:result) { analysis.call(rows) }

    let(:rows) do
      [
        # alice: came back twice, 2h and 4h; once never came back
        wait('alice', pushed: et(1, 9), returned: et(1, 11), number: 1),
        wait('alice', pushed: et(2, 9), returned: et(2, 13), number: 2),
        wait('alice', pushed: et(3, 9), number: 3),
        # bob: never came back at all
        wait('bob', pushed: et(1, 9), number: 4)
      ]
    end

    it 'measures from the push, not from the original review' do
      alice = result[:reviewer_stats].find { |s| s[:reviewer_login] == 'alice' }

      expect(alice[:median_hours]).to eq(3.0) # median of 2h and 4h
    end

    it 'reports how often each person came back' do
      alice = result[:reviewer_stats].find { |s| s[:reviewer_login] == 'alice' }

      expect(alice[:waits]).to eq(3)
      expect(alice[:returned]).to eq(2)
      expect(alice[:return_rate]).to eq(66.7)
    end

    it 'gives a reviewer who never returned a rate of zero and no median' do
      bob = result[:reviewer_stats].find { |s| s[:reviewer_login] == 'bob' }

      expect(bob[:return_rate]).to eq(0)
      expect(bob[:median_hours]).to be_nil
    end

    it 'summarises the team' do
      expect(result[:total_waits]).to eq(4)
      expect(result[:total_returned]).to eq(2)
      expect(result[:overall_return_rate]).to eq(50.0)
      expect(result[:overall_median_hours]).to eq(3.0)
    end

    it 'orders reviewers by how often they were waited on' do
      expect(result[:reviewer_stats].map { |s| s[:reviewer_login] }).to eq(%w[alice bob])
    end

    it 'returns nil with no data' do
      expect(analysis.call([])).to be_nil
      expect(analysis.call(nil)).to be_nil
    end
  end

  # The point of starting the clock at the push: a reviewer should not look slow
  # because the author took a week to make the changes.
  it 'does not count the time the author spent working' do
    rows = [wait('alice', pushed: et(3, 9), returned: et(3, 10))]

    expect(described_class.new.call(rows)[:overall_median_hours]).to eq(1.0)
  end

  it 'counts only working hours between push and return' do
    # Friday 17:00 push, Monday 09:00 return -> 1h Friday + 1h Monday
    rows = [wait('alice', pushed: et(5, 17), returned: et(8, 9))]

    expect(described_class.new.call(rows)[:overall_median_hours]).to eq(2.0)
  end

  it 'accepts an injected business-hours calculator' do
    calc = ReviewLens::Calculators::BusinessHours.new(start_hour: 0, end_hour: 24)
    rows = [wait('alice', pushed: et(1, 9), returned: et(1, 12))]

    expect(described_class.new(business_hours: calc).call(rows)[:overall_median_hours]).to eq(3.0)
  end
end
