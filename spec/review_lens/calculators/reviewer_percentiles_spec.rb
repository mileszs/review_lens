# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::ReviewerPercentiles do
  let(:reviewers) do
    [
      { name: 'a', bot: false, approval_pct: 90.0, actionable: 10 },
      { name: 'b', bot: false, approval_pct: 70.0, actionable: 10 },
      { name: 'c', bot: false, approval_pct: 50.0, actionable: 10 },
      { name: 'lowvol', bot: false, approval_pct: 80.0, actionable: 2 }, # below min_sample
      { name: 'github-actions', bot: true, approval_pct: 100.0, actionable: 99 }, # excluded
      { name: 'nodata', bot: false, approval_pct: nil, actionable: 10 } # non-numeric
    ]
  end

  describe '#for_metric' do
    it 'computes median and below/above shares over the eligible non-bot cohort' do
      result = described_class.new(reviewers, 'a').for_metric(:approval_pct, min_sample_key: :actionable, min_sample: 5)

      # eligible: a(90), b(70), c(50) — bot, low-volume, and nil are excluded
      expect(result[:values]).to eq([50.0, 70.0, 90.0])
      expect(result[:median]).to eq(70.0)
      expect(result[:value]).to eq(90.0)
      expect(result[:count]).to eq(3)
      expect(result[:pct_below]).to eq(67) # 2 of 3 are below 90
      expect(result[:pct_above]).to eq(0)
    end

    it 'reports below/above shares for a middle reviewer' do
      result = described_class.new(reviewers, 'b').for_metric(:approval_pct, min_sample_key: :actionable, min_sample: 5)
      expect(result[:pct_below]).to eq(33) # 1 of 3 below 70
      expect(result[:pct_above]).to eq(33) # 1 of 3 above 70
    end

    it 'returns nil when the focus reviewer is below the minimum sample' do
      result = described_class.new(reviewers, 'lowvol').for_metric(:approval_pct, min_sample_key: :actionable,
                                                                                  min_sample: 5)
      expect(result).to be_nil
    end

    it 'returns nil when the focus reviewer has no value for the metric' do
      result = described_class.new(reviewers, 'nodata').for_metric(:approval_pct, min_sample_key: :actionable,
                                                                                  min_sample: 5)
      expect(result).to be_nil
    end

    it 'excludes bots from the cohort even without a min sample' do
      result = described_class.new(reviewers, 'a').for_metric(:approval_pct)
      # lowvol(80) now eligible (no min sample); bot still excluded
      expect(result[:values]).to eq([50.0, 70.0, 80.0, 90.0])
      expect(result[:count]).to eq(4)
    end

    # A "team median" drawn from one person is not a comparison. Saying nothing
    # is better than saying something confident and meaningless.
    context 'when the eligible cohort is too small' do
      let(:tiny) do
        [
          { name: 'a', bot: false, approval_pct: 90.0, actionable: 10 },
          { name: 'b', bot: false, approval_pct: 70.0, actionable: 10 }
        ]
      end

      it 'returns nil rather than comparing against fewer than three people' do
        result = described_class.new(tiny, 'a').for_metric(:approval_pct)

        expect(result).to be_nil
      end

      it 'returns nil when the focus reviewer is the only eligible person' do
        solo = [{ name: 'a', bot: false, approval_pct: 90.0, actionable: 10 }]

        expect(described_class.new(solo, 'a').for_metric(:approval_pct)).to be_nil
      end
    end
  end
end
