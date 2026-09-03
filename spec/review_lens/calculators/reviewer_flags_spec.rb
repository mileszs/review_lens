# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::ReviewerFlags do
  describe '.response_delay_flag?' do
    it 'returns false for nil delta' do
      expect(described_class.response_delay_flag?(delta: nil, sample_size: 10)).to be false
    end

    it 'returns false for nil sample_size' do
      expect(described_class.response_delay_flag?(delta: 10, sample_size: nil)).to be false
    end

    it 'returns false when delta is below threshold' do
      expect(described_class.response_delay_flag?(delta: 4.9, sample_size: 10)).to be false
    end

    it 'returns false when sample_size is below minimum' do
      expect(described_class.response_delay_flag?(delta: 10, sample_size: 4)).to be false
    end

    it 'returns true when delta exceeds threshold with sufficient samples' do
      expect(described_class.response_delay_flag?(delta: 5.1, sample_size: 5)).to be true
    end

    it 'returns true for large delays' do
      # erin from data.js: delta=17.5, n=29
      expect(described_class.response_delay_flag?(delta: 17.5, sample_size: 29)).to be true
    end
  end

  describe '.low_effectiveness_flag?' do
    it 'returns false for nil rate' do
      expect(described_class.low_effectiveness_flag?(rate: nil, count: 5)).to be false
    end

    it 'returns false for nil count' do
      expect(described_class.low_effectiveness_flag?(rate: 50, count: nil)).to be false
    end

    it 'returns false when rate is at or above threshold' do
      expect(described_class.low_effectiveness_flag?(rate: 75, count: 5)).to be false
    end

    it 'returns false when count is below minimum' do
      expect(described_class.low_effectiveness_flag?(rate: 50, count: 1)).to be false
    end

    it 'returns true when rate is low with sufficient samples' do
      # dana from data.js: rate=50%, count=2
      expect(described_class.low_effectiveness_flag?(rate: 50, count: 2)).to be true
    end
  end

  describe '.badges' do
    it 'returns empty array for unremarkable reviewer' do
      reviewer = { approval_pct: 80, actionable: 10, minimal: 2, brief: 3, substantive: 5 }
      expect(described_class.badges(reviewer)).to eq([])
    end

    it 'includes :rubber_stamp for >95% approval with 5+ actionable' do
      reviewer = { approval_pct: 98, actionable: 10 }
      expect(described_class.badges(reviewer)).to include(:rubber_stamp)
    end

    it 'excludes :rubber_stamp when actionable < 5' do
      reviewer = { approval_pct: 100, actionable: 4 }
      expect(described_class.badges(reviewer)).not_to include(:rubber_stamp)
    end

    it 'includes :load_bearing for >150% ratio with 5+ reviews' do
      reviewer = { ratio: 200, prs_reviewed: 10, prs_authored: 5 }
      expect(described_class.badges(reviewer)).to include(:load_bearing)
    end

    it 'includes :under_contributing for <50% ratio with 5+ authored' do
      reviewer = { ratio: 40, prs_reviewed: 4, prs_authored: 10 }
      expect(described_class.badges(reviewer)).to include(:under_contributing)
    end

    it 'can return multiple badges' do
      reviewer = {
        approval_pct: 97.8, actionable: 91,
        ratio: 202, prs_reviewed: 89, prs_authored: 44
      }
      badges = described_class.badges(reviewer)
      expect(badges).to include(:rubber_stamp)
      expect(badges).to include(:load_bearing)
    end
  end

  describe '.any_flag?' do
    it 'returns false for unflagged reviewer' do
      reviewer = {
        approval_pct: 80, actionable: 10,
        minimal: 2, brief: 3, substantive: 5,
        response_delta: 1, response_n: 10,
        chg_req_rate: 100, changes_requested: 5,
        ratio: 100, prs_reviewed: 10, prs_authored: 10
      }
      expect(described_class.any_flag?(reviewer)).to be false
    end

    it 'returns true for rubber-stamp flag' do
      reviewer = { approval_pct: 98, actionable: 10 }
      expect(described_class.any_flag?(reviewer)).to be true
    end

    it 'returns true for response delay flag' do
      reviewer = { response_delta: 10, response_n: 10 }
      expect(described_class.any_flag?(reviewer)).to be true
    end

    it 'returns true for low effectiveness flag' do
      reviewer = { chg_req_rate: 50, changes_requested: 5 }
      expect(described_class.any_flag?(reviewer)).to be true
    end

    it 'returns true for high ratio flag' do
      reviewer = { ratio: 200, prs_reviewed: 10, prs_authored: 5 }
      expect(described_class.any_flag?(reviewer)).to be true
    end

    it 'returns true for low ratio flag' do
      reviewer = { ratio: 30, prs_reviewed: 3, prs_authored: 10 }
      expect(described_class.any_flag?(reviewer)).to be true
    end
  end

  describe '.ratio_flag' do
    it 'returns nil for nil ratio' do
      expect(described_class.ratio_flag(ratio: nil, prs_reviewed: 10, prs_authored: 10)).to be_nil
    end

    it 'returns :high for >150% with 5+ reviews' do
      expect(described_class.ratio_flag(ratio: 200, prs_reviewed: 10, prs_authored: 5)).to eq(:high)
    end

    it 'returns nil for >150% with <5 reviews' do
      expect(described_class.ratio_flag(ratio: 200, prs_reviewed: 4, prs_authored: 2)).to be_nil
    end

    it 'returns :low for <50% with 5+ authored' do
      expect(described_class.ratio_flag(ratio: 30, prs_reviewed: 3, prs_authored: 10)).to eq(:low)
    end

    it 'returns nil for <50% with <5 authored' do
      expect(described_class.ratio_flag(ratio: 30, prs_reviewed: 1, prs_authored: 4)).to be_nil
    end

    it 'returns nil for normal ratio' do
      expect(described_class.ratio_flag(ratio: 100, prs_reviewed: 10, prs_authored: 10)).to be_nil
    end
  end
end
