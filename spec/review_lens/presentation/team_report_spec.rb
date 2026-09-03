# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Presentation::TeamReport do
  subject(:reporter) do
    described_class.new(
      metrics: metrics,
      week_start: week_start,
      week_end: week_end,
      config: config
    )
  end

  let(:week_start) { Time.parse('2026-01-29 00:00:00 UTC') }
  let(:week_end) { Time.parse('2026-04-29 00:00:00 UTC') }
  let(:config) { build_config(repo: 'acme/widgets') }

  let(:reviewer_stats) do
    [
      ReviewLens::Models::ReviewerStats.new(
        reviewer_login: 'alice',
        approved_count: 45,
        changes_requested_count: 12,
        commented_count: 30,
        minimal_count: 40,
        brief_count: 25,
        substantive_count: 22,
        prs_authored: 15
      ),
      ReviewLens::Models::ReviewerStats.new(
        reviewer_login: 'bob',
        approved_count: 30,
        changes_requested_count: 5,
        commented_count: 15,
        minimal_count: 30,
        brief_count: 10,
        substantive_count: 10,
        prs_authored: 20
      ),
      ReviewLens::Models::ReviewerStats.new(
        reviewer_login: 'github-actions',
        approved_count: 0,
        changes_requested_count: 0,
        commented_count: 100,
        minimal_count: 100,
        brief_count: 0,
        substantive_count: 0,
        prs_authored: 0
      )
    ]
  end

  let(:metrics) do
    {
      reviewer_stats: reviewer_stats,
      total_reviewers: 3,
      total_reviews: 237,
      review_rounds: {
        total_prs: 150,
        distribution: { 1 => 120, 2 => 25, '3+' => 5 },
        median: 1,
        mean: 1.3,
        max: 4
      },
      distribution: {
        gini: 0.35,
        bus_factor: 4,
        top_reviewer_share: 22,
        top_3_share: 55,
        health: :healthy
      },
      cross_squad: {
        same_squad_reviews: 100,
        cross_squad_reviews: 80,
        external_reviews: 57,
        cross_squad_rate: 44.4,
        reviewer_stats: [
          { reviewer_login: 'alice', same_squad: 20, cross_squad: 37, cross_squad_rate: 64.9 }
        ]
      },
      response_times: {
        overall_median_hours: 1.2,
        total_requests: 200,
        responded_count: 150,
        reviewer_stats: [
          { reviewer_login: 'alice', median_hours: 0.8, review_count: 45 }
        ],
        rereview_metrics: {
          reviewer_stats: [
            { reviewer_login: 'alice', median_hours: 0.6 }
          ]
        },
        comparison_stats: [
          { reviewer_login: 'alice', initial_hours: 0.8, rereview_hours: 0.6, delta_hours: -0.2 }
        ]
      },
      effectiveness: {
        total_changes_requested: 17,
        total_effective: 15,
        overall_effectiveness_rate: 88.2,
        reviewer_stats: [
          { reviewer_login: 'alice', changes_requested_count: 12, effective_count: 11, effectiveness_rate: 91.7 }
        ]
      },
      review_author_ratio: {
        stats: [
          { login: 'alice', prs_reviewed: 50, prs_authored: 15, ratio: 333 },
          { login: 'bob', prs_reviewed: 35, prs_authored: 20, ratio: 175 }
        ],
        total_people: 3,
        high_ratio_count: 2,
        low_ratio_count: 0
      }
    }
  end

  describe '#render' do
    subject(:html) { reporter.render }

    it 'returns a string' do
      expect(html).to be_a(String)
    end

    it 'produces valid HTML document structure' do
      expect(html).to include('<!DOCTYPE html>')
      expect(html).to include('<html')
      expect(html).to include('</html>')
    end

    it 'includes the title' do
      expect(html).to include('PR Reviewer Metrics')
    end

    it 'includes inlined CSS' do
      expect(html).to include('<style>')
      expect(html).to include('--paper')
    end

    it 'includes inlined JavaScript' do
      expect(html).to include('<script>')
      expect(html).to include('setupTocHighlighting')
    end

    it 'includes repository name' do
      expect(html).to include('acme/widgets')
    end

    it 'includes reviewer names' do
      expect(html).to include('alice')
      expect(html).to include('bob')
    end

    it 'includes KPI values' do
      expect(html).to include('237')
      expect(html).to include('3')
    end

    it 'includes master table with data attributes' do
      expect(html).to include('data-row')
      expect(html).to include('data-sort-key')
    end

    it 'includes SVG visualizations' do
      expect(html).to include('<svg')
      expect(html).to include('</svg>')
    end

    it 'includes section anchors' do
      expect(html).to include('id="hero"')
      expect(html).to include('id="concentration"')
      expect(html).to include('id="methodology"')
    end
  end

  describe '#write' do
    let(:tmp_path) { '/tmp/test_reviewer_report.html' }

    after do
      FileUtils.rm_f(tmp_path)
    end

    it 'writes the HTML to a file' do
      reporter.write(tmp_path)
      expect(File.exist?(tmp_path)).to be true
    end

    it 'writes valid HTML content' do
      reporter.write(tmp_path)
      content = File.read(tmp_path)
      expect(content).to include('<!DOCTYPE html>')
    end
  end

  describe 'helper methods' do
    describe '#format_hours' do
      it 'formats hours greater than 1 with h suffix' do
        expect(reporter.send(:format_hours, 2.5)).to eq('2.5h')
      end

      it 'formats minutes for values less than 1 hour' do
        expect(reporter.send(:format_hours, 0.5)).to eq('30m')
      end

      it 'returns dash for nil' do
        expect(reporter.send(:format_hours, nil)).to eq('—')
      end
    end

    describe '#format_delta' do
      it 'includes plus sign for positive values' do
        expect(reporter.send(:format_delta, 1.5)).to eq('+1.5h')
      end

      it 'handles negative values' do
        expect(reporter.send(:format_delta, -0.5)).to eq('-30m')
      end
    end

    describe '#format_pct' do
      it 'formats percentage with one decimal' do
        expect(reporter.send(:format_pct, 45.67)).to eq('45.7%')
      end

      it 'returns dash for nil' do
        expect(reporter.send(:format_pct, nil)).to eq('—')
      end
    end

    describe '#severity_class' do
      it 'returns high class for high severity' do
        expect(reporter.send(:severity_class, :high)).to eq('watch--high')
      end

      it 'returns medium class for medium severity' do
        expect(reporter.send(:severity_class, :medium)).to eq('watch--medium')
      end
    end

    describe '#lorenz_curve_path' do
      it 'generates SVG path string' do
        path = reporter.send(:lorenz_curve_path)
        expect(path).to include('M')
        expect(path).to include('L')
      end
    end
  end

  describe 'with empty metrics' do
    let(:metrics) { { reviewer_stats: [] } }

    it 'renders without error' do
      expect { reporter.render }.not_to raise_error
    end

    it 'produces valid HTML' do
      html = reporter.render
      expect(html).to include('<!DOCTYPE html>')
    end
  end

  describe 'with minimal metrics' do
    let(:reviewer_stats) do
      [
        ReviewLens::Models::ReviewerStats.new(
          reviewer_login: 'solo',
          approved_count: 10,
          changes_requested_count: 2,
          commented_count: 5
        )
      ]
    end

    let(:metrics) do
      {
        reviewer_stats: reviewer_stats,
        total_reviewers: 1,
        total_reviews: 17
      }
    end

    it 'handles missing optional metrics gracefully' do
      expect { reporter.render }.not_to raise_error
    end
  end
end
