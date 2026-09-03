# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Models::ReviewerStats do
  describe '#initialize' do
    it 'sets all attributes' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        changes_requested_count: 3,
        commented_count: 2
      )

      expect(stats.reviewer_login).to eq('alice')
      expect(stats.approved_count).to eq(10)
      expect(stats.changes_requested_count).to eq(3)
      expect(stats.commented_count).to eq(2)
    end

    it 'defaults counts to 0' do
      stats = described_class.new(reviewer_login: 'alice')

      expect(stats.approved_count).to eq(0)
      expect(stats.changes_requested_count).to eq(0)
      expect(stats.commented_count).to eq(0)
    end
  end

  describe '#total_reviews' do
    it 'sums all review types' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        changes_requested_count: 3,
        commented_count: 2
      )

      expect(stats.total_reviews).to eq(15)
    end

    it 'returns 0 when all counts are 0' do
      stats = described_class.new(reviewer_login: 'alice')

      expect(stats.total_reviews).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true when total_reviews is 0' do
      stats = described_class.new(reviewer_login: 'alice')

      expect(stats.empty?).to be true
    end

    it 'returns false when there are reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 1
      )

      expect(stats.empty?).to be false
    end
  end

  describe '#approval_rate' do
    it 'calculates percentage of approvals among actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 8,
        changes_requested_count: 2,
        commented_count: 5
      )

      expect(stats.approval_rate).to eq(80.0)
    end

    it 'returns nil when no actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        commented_count: 5
      )

      expect(stats.approval_rate).to be_nil
    end

    it 'returns 100% when all actionable reviews are approvals' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        commented_count: 3
      )

      expect(stats.approval_rate).to eq(100.0)
    end
  end

  describe '#change_request_rate' do
    it 'calculates percentage of change requests among actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 8,
        changes_requested_count: 2
      )

      expect(stats.change_request_rate).to eq(20.0)
    end

    it 'returns nil when no actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        commented_count: 5
      )

      expect(stats.change_request_rate).to be_nil
    end
  end

  describe '#high_approval_rate?' do
    it 'returns true when approval rate >= 95% with 5+ actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 19,
        changes_requested_count: 1
      )

      expect(stats.high_approval_rate?).to be true
    end

    it 'returns false when approval rate < 95%' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 8,
        changes_requested_count: 2
      )

      expect(stats.high_approval_rate?).to be false
    end

    it 'returns false when fewer than 5 actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 4,
        changes_requested_count: 0
      )

      expect(stats.high_approval_rate?).to be false
    end

    it 'returns false when no actionable reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        commented_count: 10
      )

      expect(stats.high_approval_rate?).to be false
    end
  end

  describe '.categorize_depth' do
    it 'returns :minimal for empty body' do
      expect(described_class.categorize_depth(nil)).to eq(:minimal)
      expect(described_class.categorize_depth('')).to eq(:minimal)
      expect(described_class.categorize_depth('   ')).to eq(:minimal)
    end

    it 'returns :minimal for body under 10 chars' do
      expect(described_class.categorize_depth('LGTM')).to eq(:minimal)
      expect(described_class.categorize_depth('OK')).to eq(:minimal)
    end

    it 'returns :brief for body 10-100 chars' do
      expect(described_class.categorize_depth('Looks good to me!')).to eq(:brief)
      expect(described_class.categorize_depth('a' * 50)).to eq(:brief)
      expect(described_class.categorize_depth('a' * 99)).to eq(:brief)
    end

    it 'returns :substantive for body over 100 chars' do
      expect(described_class.categorize_depth('a' * 100)).to eq(:substantive)
      expect(described_class.categorize_depth('a' * 500)).to eq(:substantive)
    end
  end

  describe '#total_with_depth' do
    it 'sums all depth categories' do
      stats = described_class.new(
        reviewer_login: 'alice',
        minimal_count: 2,
        brief_count: 5,
        substantive_count: 3
      )

      expect(stats.total_with_depth).to eq(10)
    end
  end

  describe '#depth_score' do
    it 'calculates percentage of substantive reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        minimal_count: 2,
        brief_count: 3,
        substantive_count: 5
      )

      expect(stats.depth_score).to eq(50.0)
    end

    it 'returns nil when no depth data' do
      stats = described_class.new(reviewer_login: 'alice')

      expect(stats.depth_score).to be_nil
    end

    it 'returns 100% when all reviews are substantive' do
      stats = described_class.new(
        reviewer_login: 'alice',
        substantive_count: 10
      )

      expect(stats.depth_score).to eq(100.0)
    end
  end

  describe '#shallow_reviewer?' do
    it 'returns true when >50% minimal with 5+ reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        minimal_count: 6,
        brief_count: 2,
        substantive_count: 2
      )

      expect(stats.shallow_reviewer?).to be true
    end

    it 'returns false when minimal is 50% or less' do
      stats = described_class.new(
        reviewer_login: 'alice',
        minimal_count: 5,
        brief_count: 3,
        substantive_count: 2
      )

      expect(stats.shallow_reviewer?).to be false
    end

    it 'returns false when fewer than 5 reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        minimal_count: 4
      )

      expect(stats.shallow_reviewer?).to be false
    end
  end

  describe '#prs_authored' do
    it 'defaults to 0' do
      stats = described_class.new(reviewer_login: 'alice')

      expect(stats.prs_authored).to eq(0)
    end

    it 'can be set via initializer' do
      stats = described_class.new(reviewer_login: 'alice', prs_authored: 15)

      expect(stats.prs_authored).to eq(15)
    end
  end

  describe '#review_author_ratio' do
    it 'calculates ratio of reviews to PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 15,
        changes_requested_count: 5,
        prs_authored: 10
      )

      # 20 reviews / 10 PRs = 200%
      expect(stats.review_author_ratio).to eq(200)
    end

    it 'returns nil when no PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        prs_authored: 0
      )

      expect(stats.review_author_ratio).to be_nil
    end

    it 'handles balanced reviewer (100%)' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        prs_authored: 10
      )

      expect(stats.review_author_ratio).to eq(100)
    end

    it 'handles reviewer who reviews less than they author' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 5,
        prs_authored: 20
      )

      expect(stats.review_author_ratio).to eq(25)
    end
  end

  describe '#high_review_ratio?' do
    it 'returns true when ratio >150% with 5+ reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 8,
        changes_requested_count: 2,
        prs_authored: 5
      )

      # 10 reviews / 5 PRs = 200%
      expect(stats.high_review_ratio?).to be true
    end

    it 'returns false when ratio <= 150%' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 6,
        prs_authored: 5
      )

      # 6 reviews / 5 PRs = 120%
      expect(stats.high_review_ratio?).to be false
    end

    it 'returns false when fewer than 5 reviews' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 4,
        prs_authored: 1
      )

      # 4 reviews / 1 PR = 400%, but only 4 reviews
      expect(stats.high_review_ratio?).to be false
    end

    it 'returns false when no PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        prs_authored: 0
      )

      expect(stats.high_review_ratio?).to be false
    end
  end

  describe '#low_review_ratio?' do
    it 'returns true when ratio <50% with 5+ PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 2,
        prs_authored: 10
      )

      # 2 reviews / 10 PRs = 20%
      expect(stats.low_review_ratio?).to be true
    end

    it 'returns false when ratio >= 50%' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 5,
        prs_authored: 10
      )

      # 5 reviews / 10 PRs = 50%
      expect(stats.low_review_ratio?).to be false
    end

    it 'returns false when fewer than 5 PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 0,
        prs_authored: 4
      )

      # 0 reviews / 4 PRs = 0%, but only 4 PRs authored
      expect(stats.low_review_ratio?).to be false
    end

    it 'returns false when no PRs authored' do
      stats = described_class.new(
        reviewer_login: 'alice',
        approved_count: 10,
        prs_authored: 0
      )

      expect(stats.low_review_ratio?).to be false
    end
  end
end
