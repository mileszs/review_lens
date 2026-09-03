# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Presentation::WatchList do
  describe '.derive' do
    let(:empty_meta) { { bus_factor: 5, gini: 0.4, top_3_share: 30.0 } }
    let(:empty_reviewers) { [] }

    it 'returns empty array when no patterns match' do
      meta = { bus_factor: 10, gini: 0.2, top_3_share: 20.0 }
      reviewers = [{ name: 'alice', approval_pct: 70, actionable: 10, depth_pct: 50 }]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      # Only bus_factor callout should be present (always shown)
      expect(result.length).to eq(1)
      expect(result.first[:title]).to include('Bus factor')
    end
  end

  describe 'rereview_delay_callouts' do
    it 'triggers for reviewer with high delta and sufficient samples' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [{
        name: 'erin',
        response_initial: 0.3,
        response_re_review: 17.8,
        response_delta: 17.5,
        response_n: 29
      }]
      result = described_class.derive(meta: meta, reviewers: reviewers)

      delay_callout = result.find { |c| c[:title].include?('re-review delay') }
      expect(delay_callout).not_to be_nil
      expect(delay_callout[:severity]).to eq(:high)
      expect(delay_callout[:refs]).to eq(['erin'])
    end

    it 'does not trigger when delta is below threshold' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [{
        name: 'alice',
        response_delta: 4.0,
        response_n: 10
      }]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title].include?('re-review delay') }).to be false
    end

    it 'does not trigger when sample size is too small' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [{
        name: 'alice',
        response_delta: 10.0,
        response_n: 3
      }]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title].include?('re-review delay') }).to be false
    end
  end

  describe 'rubber_stamp_callout' do
    it 'triggers when 3+ reviewers meet criteria' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'alice', approval_pct: 98, depth_pct: 10, actionable: 20 },
        { name: 'bob', approval_pct: 97, depth_pct: 12, actionable: 15 },
        { name: 'charlie', approval_pct: 99, depth_pct: 5, actionable: 10 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)

      stamp_callout = result.find { |c| c[:title] == 'Rubber-stamp cluster' }
      expect(stamp_callout).not_to be_nil
      expect(stamp_callout[:severity]).to eq(:medium)
      expect(stamp_callout[:refs]).to include('alice', 'bob', 'charlie')
    end

    it 'does not trigger with fewer than 3 matching reviewers' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'alice', approval_pct: 98, depth_pct: 10, actionable: 20 },
        { name: 'bob', approval_pct: 97, depth_pct: 12, actionable: 15 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title] == 'Rubber-stamp cluster' }).to be false
    end

    it 'excludes bots from rubber-stamp detection' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'github-actions', bot: true, approval_pct: 100, depth_pct: 0, actionable: 100 },
        { name: 'alice', approval_pct: 98, depth_pct: 10, actionable: 20 },
        { name: 'bob', approval_pct: 97, depth_pct: 12, actionable: 15 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title] == 'Rubber-stamp cluster' }).to be false
    end
  end

  describe 'bus_factor_callout' do
    it 'always includes bus factor callout' do
      meta = { bus_factor: 5, gini: 0.49, top_3_share: 37.7 }
      result = described_class.derive(meta: meta, reviewers: [])

      bus_callout = result.find { |c| c[:title].include?('Bus factor') }
      expect(bus_callout).not_to be_nil
      expect(bus_callout[:title]).to eq('Bus factor of 5')
    end

    it 'is medium severity when bus factor > 3' do
      meta = { bus_factor: 5, gini: 0.4 }
      result = described_class.derive(meta: meta, reviewers: [])

      bus_callout = result.find { |c| c[:title].include?('Bus factor') }
      expect(bus_callout[:severity]).to eq(:medium)
    end

    it 'is high severity when bus factor <= 3' do
      meta = { bus_factor: 2, gini: 0.6 }
      result = described_class.derive(meta: meta, reviewers: [])

      bus_callout = result.find { |c| c[:title].include?('Bus factor') }
      expect(bus_callout[:severity]).to eq(:high)
    end
  end

  describe 'low_ratio_callout' do
    it 'triggers for non-bots with authored >= 5 and ratio < 25%' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'mileszs', ratio: 2, prs_authored: 42, prs_reviewed: 1 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)

      ratio_callout = result.find { |c| c[:title] == 'Authors not reviewing back' }
      expect(ratio_callout).not_to be_nil
      expect(ratio_callout[:severity]).to eq(:low)
      expect(ratio_callout[:refs]).to include('mileszs')
    end

    it 'excludes bots' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'dependabot', bot: true, ratio: 0, prs_authored: 100, prs_reviewed: 0 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title] == 'Authors not reviewing back' }).to be false
    end

    it 'does not trigger when ratio >= 25%' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'alice', ratio: 30, prs_authored: 10, prs_reviewed: 3 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title] == 'Authors not reviewing back' }).to be false
    end
  end

  describe 'changes_req_followthrough_callouts' do
    it 'triggers for reviewers with low effectiveness rate' do
      meta = { bus_factor: 5, gini: 0.4, review_effectiveness_overall: 97.1 }
      reviewers = [
        { name: 'dana', chg_req_rate: 50.0, changes_requested: 2 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)

      followthrough = result.find { |c| c[:title].include?('follow-through') }
      expect(followthrough).not_to be_nil
      expect(followthrough[:severity]).to eq(:low)
      expect(followthrough[:body]).to include('50%')
      expect(followthrough[:body]).to include('97.1%')
    end

    it 'does not trigger when rate >= 75%' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'alice', chg_req_rate: 80.0, changes_requested: 5 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title].include?('follow-through') }).to be false
    end

    it 'does not trigger when changes_requested < 2' do
      meta = { bus_factor: 5, gini: 0.4 }
      reviewers = [
        { name: 'alice', chg_req_rate: 0.0, changes_requested: 1 }
      ]
      result = described_class.derive(meta: meta, reviewers: reviewers)
      expect(result.any? { |c| c[:title].include?('follow-through') }).to be false
    end
  end
end
