# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Presentation::DataMapper do
  subject(:mapper) { described_class.new(metrics: metrics, week_start: week_start, week_end: week_end, config: config) }

  let(:week_start) { Time.parse('2026-01-29 00:00:00 UTC') }
  let(:week_end) { Time.parse('2026-04-29 00:00:00 UTC') }
  let(:config) { build_config(repo: 'acme/widgets') }

  let(:reviewer_stats) do
    [
      ReviewLens::Models::ReviewerStats.new(
        reviewer_login: 'bob',
        approved_count: 95,
        changes_requested_count: 34,
        commented_count: 98,
        minimal_count: 133,
        brief_count: 42,
        substantive_count: 54,
        prs_authored: 68
      ),
      ReviewLens::Models::ReviewerStats.new(
        reviewer_login: 'github-actions',
        approved_count: 0,
        changes_requested_count: 0,
        commented_count: 316,
        minimal_count: 316,
        brief_count: 0,
        substantive_count: 0,
        prs_authored: 0
      )
    ]
  end

  let(:metrics) do
    {
      reviewer_stats: reviewer_stats,
      total_reviewers: 25,
      total_reviews: 543,
      review_rounds: {
        total_prs: 663,
        distribution: { 1 => 552, 2 => 84, '3+' => 27 },
        median: 1,
        mean: 1.21,
        max: 4
      },
      distribution: {
        gini: 0.49,
        bus_factor: 5,
        top_reviewer_share: 16,
        top_3_share: 37.7,
        health: :moderate
      },
      cross_squad: {
        same_squad_reviews: 471,
        cross_squad_reviews: 350,
        external_reviews: 629,
        cross_squad_rate: 42.6,
        reviewer_stats: [
          { reviewer_login: 'bob', same_squad: 13, cross_squad: 156, cross_squad_rate: 92.3 }
        ]
      },
      response_times: {
        overall_median_hours: 1.4,
        total_requests: 715,
        responded_count: 454,
        reviewer_stats: [
          { reviewer_login: 'bob', median_hours: 0.9, review_count: 36 }
        ],
        rereview_metrics: {
          reviewer_stats: [
            { reviewer_login: 'bob', median_hours: 0.8 }
          ]
        },
        comparison_stats: [
          { reviewer_login: 'bob', initial_hours: 0.9, rereview_hours: 0.8, delta_hours: -0.1 }
        ]
      },
      effectiveness: {
        total_changes_requested: 69,
        total_effective: 67,
        overall_effectiveness_rate: 97.1,
        reviewer_stats: [
          { reviewer_login: 'bob', changes_requested_count: 34, effective_count: 34, effectiveness_rate: 100.0 }
        ]
      },
      review_author_ratio: {
        stats: [
          { login: 'bob', prs_reviewed: 111, prs_authored: 68, ratio: 163 }
        ],
        total_people: 25,
        high_ratio_count: 8,
        low_ratio_count: 6
      }
    }
  end

  describe '#report_meta' do
    subject(:meta) { mapper.report_meta }

    it 'includes repository name' do
      expect(meta[:repo]).to eq('acme/widgets')
    end

    it 'formats period dates' do
      expect(meta[:period_start]).to eq('Jan 29, 2026')
      expect(meta[:period_end]).to eq('Apr 29, 2026')
    end

    it 'includes reviewer totals' do
      expect(meta[:total_reviewers]).to eq(25)
      expect(meta[:total_reviews]).to eq(543)
    end

    it 'includes PR statistics' do
      expect(meta[:total_prs]).to eq(663)
      expect(meta[:median_reviews_per_pr]).to eq(1)
      expect(meta[:mean_reviews_per_pr]).to eq(1.21)
      expect(meta[:max_reviews_on_pr]).to eq(4)
    end

    it 'includes distribution metrics' do
      expect(meta[:bus_factor]).to eq(5)
      expect(meta[:gini]).to eq(0.49)
      expect(meta[:top_share]).to eq(16)
      expect(meta[:top_3_share]).to eq(37.7)
    end

    it 'formats health status' do
      expect(meta[:health]).to eq('Moderate — Some concentration')
    end

    it 'maps PR distribution' do
      expect(meta[:pr_distribution]).to eq([
                                             { bucket: '1 review', prs: 552, pct: 83.3 },
                                             { bucket: '2 reviews', prs: 84, pct: 12.7 },
                                             { bucket: '3+ reviews', prs: 27, pct: 4.1 }
                                           ])
    end

    it 'includes cross-squad metrics' do
      expect(meta[:cross_squad][:same]).to eq(471)
      expect(meta[:cross_squad][:cross]).to eq(350)
      expect(meta[:cross_squad][:rate]).to eq(42.6)
    end

    it 'includes response time metrics' do
      expect(meta[:response_initial_median]).to eq(1.4)
      expect(meta[:response_requests]).to eq(715)
      expect(meta[:response_completed]).to eq(454)
    end

    it 'includes effectiveness metrics' do
      expect(meta[:review_effectiveness_overall]).to eq(97.1)
      expect(meta[:changes_requested_total]).to eq(69)
      expect(meta[:changes_requested_followed_by_commit]).to eq(67)
    end
  end

  describe '#reviewers' do
    subject(:reviewers) { mapper.reviewers }

    it 'returns all reviewers' do
      expect(reviewers.length).to eq(2)
    end

    describe 'human reviewer (bob)' do
      subject(:reviewer) { reviewers.find { |r| r[:name] == 'bob' } }

      it 'includes basic counts' do
        expect(reviewer[:approved]).to eq(95)
        expect(reviewer[:changes_requested]).to eq(34)
        expect(reviewer[:commented]).to eq(98)
        expect(reviewer[:total]).to eq(227)
      end

      it 'computes share percentage' do
        # 227 / 543 * 100 = 41.8%
        expect(reviewer[:share_pct]).to eq(41.8)
      end

      it 'includes actionable count' do
        expect(reviewer[:actionable]).to eq(129)
      end

      it 'includes approval rate' do
        # 95 / 129 * 100 = 73.6%
        expect(reviewer[:approval_pct]).to eq(73.6)
      end

      it 'includes depth metrics' do
        expect(reviewer[:minimal]).to eq(133)
        expect(reviewer[:brief]).to eq(42)
        expect(reviewer[:substantive]).to eq(54)
        # 54 / 229 * 100 = 23.6%
        expect(reviewer[:depth_pct]).to eq(23.6)
      end

      it 'includes cross-squad data' do
        expect(reviewer[:cross_squad_same]).to eq(13)
        expect(reviewer[:cross_squad_cross]).to eq(156)
        expect(reviewer[:cross_squad_rate]).to eq(92.3)
      end

      it 'includes response time data' do
        expect(reviewer[:response_initial]).to eq(0.9)
        expect(reviewer[:response_n]).to eq(36)
        expect(reviewer[:response_re_review]).to eq(0.8)
        expect(reviewer[:response_delta]).to eq(-0.1)
      end

      it 'includes effectiveness data' do
        expect(reviewer[:chg_req_effective]).to eq(34)
        expect(reviewer[:chg_req_rate]).to eq(100.0)
      end

      it 'includes ratio data' do
        expect(reviewer[:prs_reviewed]).to eq(111)
        expect(reviewer[:prs_authored]).to eq(68)
        expect(reviewer[:ratio]).to eq(163)
      end

      it 'is not marked as bot' do
        expect(reviewer[:bot]).to be false
      end

      # Evaluative labels are opt-in. Attaching "load bearing" or
      # "under contributing" to a named person by default invites a judgement
      # the data alone cannot support, so the gem stays quiet unless asked.
      describe 'evaluative flags' do
        it 'computes no flags by default' do
          expect(reviewer[:flagged]).to be false
          expect(reviewer[:badges]).to eq([])
          expect(reviewer[:ratio_flag]).to be_nil
        end

        context 'when the user opts in with show_flags' do
          let(:config) { build_config(repo: 'acme/widgets', show_flags: true) }

          it 'computes flags, badges and the ratio flag' do
            # ratio > 150 with prs_reviewed >= 5 triggers load_bearing
            expect(reviewer[:flagged]).to be true
            expect(reviewer[:badges]).to include(:load_bearing)
            expect(reviewer[:ratio_flag]).to eq(:high)
          end
        end
      end
    end

    describe 'bot reviewer (github-actions)' do
      subject(:reviewer) { reviewers.find { |r| r[:name] == 'github-actions' } }

      it 'is marked as bot' do
        expect(reviewer[:bot]).to be true
      end

      it 'includes basic counts' do
        expect(reviewer[:total]).to eq(316)
        expect(reviewer[:commented]).to eq(316)
      end
    end
  end

  describe 'bot detection' do
    it 'detects github-actions as bot' do
      expect(mapper.reviewers.find { |r| r[:name] == 'github-actions' }[:bot]).to be true
    end

    it 'does not mark regular users as bots' do
      expect(mapper.reviewers.find { |r| r[:name] == 'bob' }[:bot]).to be false
    end
  end

  describe 'with empty metrics' do
    let(:metrics) { { reviewer_stats: [] } }

    it 'returns empty reviewers array' do
      expect(mapper.reviewers).to eq([])
    end

    it 'returns meta with defaults' do
      meta = mapper.report_meta
      expect(meta[:total_reviewers]).to eq(0)
      expect(meta[:total_reviews]).to eq(0)
    end
  end
end
