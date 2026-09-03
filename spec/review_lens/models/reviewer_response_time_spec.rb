# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Models::ReviewerResponseTime do
  describe '#initialize' do
    it 'creates a response time with all attributes' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T10:00:00Z',
        first_review_at: '2026-04-08T12:00:00Z'
      )

      expect(response_time.reviewer_login).to eq('alice')
      expect(response_time.pr_number).to eq(123)
      expect(response_time.requested_at).to eq('2026-04-08T10:00:00Z')
      expect(response_time.first_review_at).to eq('2026-04-08T12:00:00Z')
    end

    it 'calculates response hours for same-day review' do
      # 10am to 12pm ET on a weekday = 2 business hours
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T14:00:00Z', # 10am ET
        first_review_at: '2026-04-08T16:00:00Z' # 12pm ET
      )

      expect(response_time.response_hours).to eq(2.0)
    end
  end

  describe '#responded?' do
    it 'returns true when first_review_at is present' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T10:00:00Z',
        first_review_at: '2026-04-08T12:00:00Z'
      )

      expect(response_time.responded?).to be true
    end

    it 'returns false when first_review_at is nil' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T10:00:00Z',
        first_review_at: nil
      )

      expect(response_time.responded?).to be false
    end
  end

  describe 'response_hours calculation' do
    it 'returns nil when first_review_at is nil' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T10:00:00Z',
        first_review_at: nil
      )

      expect(response_time.response_hours).to be_nil
    end

    it 'accepts Time objects for timestamps' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: Time.parse('2026-04-08T14:00:00Z'),
        first_review_at: Time.parse('2026-04-08T16:00:00Z')
      )

      expect(response_time.response_hours).to eq(2.0)
    end

    it 'allows pre-calculated response_hours to be passed' do
      response_time = described_class.new(
        reviewer_login: 'alice',
        pr_number: 123,
        requested_at: '2026-04-08T10:00:00Z',
        first_review_at: '2026-04-08T12:00:00Z',
        response_hours: 5.5
      )

      expect(response_time.response_hours).to eq(5.5)
    end
  end
end
