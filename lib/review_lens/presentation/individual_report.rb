# frozen_string_literal: true

require 'erb'

module ReviewLens
  module Presentation
    # Renders a private, single-reviewer HTML report: that person's review
    # metrics for a period, positioned against the team (median + rank/percentile
    # + an anonymized distribution strip). Peers are never named — this is meant
    # to be handed to one individual.
    #
    # Reuses DataMapper (per-reviewer, login-joined data) and
    # Calculators::ReviewerPercentiles for the cohort positioning. No evaluative
    # badges/flags are shown.
    class IndividualReport
      TEMPLATE = File.expand_path('templates/individual_report/report.html.erb', __dir__)
      SHARED_CSS = File.expand_path('templates/team_report/dashboard.css', __dir__)

      # Metrics shown as "you vs team" cards. min_sample_key/min_sample gate the
      # comparison to reviewers with enough data for the metric to be meaningful.
      # direction is only used to phrase the comparison ("higher than X%" vs
      # "lower than X%"); it does not imply good/bad.
      def self.metric_definitions(min_sample)
        [
          { key: :approval_pct, label: 'Approval rate', unit: '%', direction: :high,
            min_sample_key: :actionable, min_sample: min_sample,
            note: 'Approvals as a share of your actionable reviews (approve + request-changes).' },
          { key: :depth_pct, label: 'Substantive depth', unit: '%', direction: :high,
            min_sample_key: :total, min_sample: min_sample,
            note: 'Share of your reviews with a substantive comment (vs. minimal/brief).' },
          { key: :response_initial, label: 'Initial response time', unit: 'h', direction: :low,
            min_sample_key: :response_n, min_sample: 2,
            note: 'Median business hours to your first review after a request. Lower is faster.' },
          { key: :ratio, label: 'Review / author ratio', unit: '%', direction: :high,
            min_sample_key: :prs_authored, min_sample: min_sample,
            note: 'PRs you reviewed as a share of PRs you authored.' },
          { key: :cross_team_rate, label: 'Cross-team reviews', unit: '%', direction: :high,
            min_sample_key: nil, min_sample: 0,
            note: 'Share of your reviews on PRs outside your own team.' }
        ]
      end

      def initialize(metrics:, focus_login:, week_start:, week_end:, config:)
        @mapper = DataMapper.new(metrics: metrics, week_start: week_start, week_end: week_end, config: config)
        @focus_login = focus_login
        @config = config
      end

      def render
        ERB.new(File.read(TEMPLATE), trim_mode: '-').result(binding)
      end

      def write(path)
        File.write(path, render)
      end

      private

      # A page of "not enough activity" cards is a worse artifact than saying
      # plainly that there were no reviews in the window.
      def no_activity?
        focus.nil? || focus[:total].to_i.zero?
      end

      def authored_note
        authored = focus && focus[:prs_authored].to_i
        return '' if authored.nil? || authored.zero?

        "You authored #{authored} pull request#{'s' if authored != 1} in this period."
      end

      def focus
        @focus ||= all_reviewers.find { |r| r[:name] == @focus_login }
      end

      def all_reviewers
        @all_reviewers ||= @mapper.reviewers
      end

      def meta
        @meta ||= @mapper.report_meta
      end

      def percentiles
        @percentiles ||= Calculators::ReviewerPercentiles.new(all_reviewers, @focus_login)
      end

      def metric_cards
        definitions = self.class.metric_definitions(@config.min_sample)
        # Cross-team only means something when teams are configured.
        definitions = definitions.reject { |m| m[:key] == :cross_team_rate } unless @config.teams?
        definitions.map do |metric|
          context = percentiles.for_metric(metric[:key],
                                           min_sample_key: metric[:min_sample_key],
                                           min_sample: metric[:min_sample])
          metric.merge(context: context)
        end
      end

      def period_label
        "#{meta[:period_start]} – #{meta[:period_end]}"
      end

      def inline_css
        File.read(SHARED_CSS)
      end

      # Depth mix for the focus reviewer (their own breakdown), or nil.
      def depth_mix
        counts = { minimal: focus[:minimal].to_i, brief: focus[:brief].to_i, substantive: focus[:substantive].to_i }
        total = counts.values.sum
        return nil if total.zero?

        counts.transform_values { |count| (count.to_f / total * 100).round(1) }
      end

      def fmt(value, unit)
        return '—' if value.nil?

        case unit
        when '%' then "#{trim(value)}%"
        when 'h' then value < 1 ? "#{(value * 60).round}m" : "#{trim(value)}h"
        else trim(value).to_s
        end
      end

      # Drop a trailing .0 for whole numbers, else round to 1 decimal.
      def trim(value)
        return value unless value.is_a?(Numeric)

        (value % 1).zero? ? value.to_i : value.round(1)
      end

      # Neutral, direction-aware comparison phrase (never "good/bad", never names).
      def comparison_phrase(direction, context)
        return nil unless context

        share = direction == :low ? context[:pct_above] : context[:pct_below]
        word = direction == :low ? 'lower' : 'higher'
        count = context[:count]
        "#{word} than #{share}% of the team · #{count} #{count == 1 ? 'reviewer' : 'reviewers'}"
      end

      # Anonymized distribution strip as positioned HTML dots (0-100%): unlabeled
      # peers, a median tick, and the highlighted focus dot. No SVG (avoids
      # non-uniform-scale distortion) and no peer identities.
      def distribution_strip(context)
        return '' unless context

        values = context[:values]
        dots = values.map { |value| mark('dot peer', position(value, values)) }.join
        median = mark('tick median', position(context[:median], values))
        me = mark('dot me', position(context[:value], values))
        %(<div class="strip">#{median}#{dots}#{me}</div>)
      end

      # Position (0-100%) of a value within the cohort range, padded to 8..92%.
      def position(value, values)
        span = (values.max - values.min).to_f
        return 50.0 if span.zero?

        (8 + ((value - values.min) / span * 84)).round(2)
      end

      def mark(css_class, left)
        %(<span class="#{css_class}" style="left:#{left}%"></span>)
      end

      def h(text)
        text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
