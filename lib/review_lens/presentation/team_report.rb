# frozen_string_literal: true

require 'erb'

module ReviewLens
  module Presentation
    # Renders reviewer metrics as a self-contained HTML report.
    # Produces a single .html file with inlined CSS and JS.
    class TeamReport
      TEMPLATE_DIR = File.expand_path('templates/team_report', __dir__)

      def initialize(metrics:, week_start:, week_end:, config:, anonymize: false)
        @mapper = DataMapper.new(
          metrics: metrics,
          week_start: week_start,
          week_end: week_end,
          config: config
        )
        @metrics = metrics
        @config = config
        @anonymize = anonymize
        @anonymizer = Anonymizer.new(names: config.anonymous_names) if anonymize
      end

      # Render the HTML report
      # @return [String] Complete HTML document
      def render
        template = ERB.new(File.read(template_path), trim_mode: '-')
        template.result(binding)
      end

      # Write the report to a file
      # @param output_path [String] Path to write the HTML file
      def write(output_path)
        File.write(output_path, render)
      end

      private

      # Memoized data accessors for ERB template
      def meta
        @meta ||= @mapper.report_meta
      end

      def reviewers
        @reviewers ||= begin
          data = @mapper.reviewers
          @anonymize ? @anonymizer.anonymize_reviewers(data) : data
        end
      end

      # Opt-in: the watch list is evaluative, so it is empty unless the user
      # explicitly turns flags on.
      def watch_list
        return [] unless @config.show_flags

        @watch_list ||= begin
          # Derive using raw (non-anonymized) data for accurate detection
          raw_data = @mapper.reviewers
          data = WatchList.derive(meta: meta, reviewers: raw_data)

          if @anonymize
            # Build mapping from raw data first (ensures all names are mapped)
            raw_data.each { |r| @anonymizer.anonymize(r[:name]) }
            @anonymizer.anonymize_watch_list(data)
          else
            data
          end
        end
      end

      # Read and return inlined assets
      def inline_css
        File.read(File.join(TEMPLATE_DIR, 'dashboard.css'))
      end

      def inline_js
        File.read(File.join(TEMPLATE_DIR, 'dashboard.js'))
      end

      def template_path
        File.join(TEMPLATE_DIR, 'report.html.erb')
      end

      # Heatmap color helper for ERB template
      def heatmap(value, min:, max:, invert: false, neutral: false)
        Calculators::HeatmapColor.compute(value, min: min, max: max, invert: invert, neutral: neutral)
      end

      # Format hours for display
      def format_hours(hours)
        return '—' if hours.nil?

        if hours < 1
          "#{(hours * 60).round}m"
        else
          "#{hours.round(1)}h"
        end
      end

      # Format hours with sign for delta display
      def format_delta(hours)
        return '—' if hours.nil?

        sign = hours >= 0 ? '+' : '-'
        "#{sign}#{format_hours(hours.abs)}"
      end

      # Format percentage
      def format_pct(value)
        return '—' if value.nil?

        "#{value.round(1)}%"
      end

      # Get severity class for watch list items
      def severity_class(severity)
        case severity.to_sym
        when :high then 'watch--high'
        when :medium then 'watch--medium'
        when :low then 'watch--low'
        else 'watch--low'
        end
      end

      # Get badge class and label
      def badge_info(badge)
        case badge
        when :rubber_stamp
          { class: 'badge badge--warn', label: '★ rubber-stamp' }
        when :load_bearing
          { class: 'badge badge--info', label: 'load-bearing' }
        when :under_contributing
          { class: 'badge badge--muted', label: 'under-contributing' }
        else
          { class: 'badge badge--muted', label: badge.to_s }
        end
      end

      # Generate Lorenz curve SVG path (excludes bots)
      def lorenz_curve_path
        sorted = reviewers.select { |r| !r[:bot] && r[:total].positive? }.sort_by { |r| r[:total] }
        return '' if sorted.empty?

        total = sorted.sum { |r| r[:total] }
        cum = 0
        points = [{ x: 0, y: 0 }]

        sorted.each_with_index do |r, i|
          cum += r[:total]
          points << {
            x: ((i + 1).to_f / sorted.length) * 100,
            y: (cum.to_f / total) * 100
          }
        end

        w = 280
        h = 140
        p = 8

        points.map.with_index do |pt, i|
          x = p + ((pt[:x] / 100) * (w - (2 * p)))
          y = h - p - ((pt[:y] / 100) * (h - (2 * p)))
          "#{i.zero? ? 'M' : 'L'} #{x.round(1)} #{y.round(1)}"
        end.join(' ')
      end

      # Generate share tiles data (excludes bots)
      def share_tiles_data
        sorted = reviewers.select { |r| !r[:bot] && r[:total].positive? }.sort_by { |r| -r[:total] }
        total = sorted.sum { |r| r[:total] }

        sorted.map.with_index do |r, i|
          pct = (r[:total].to_f / total * 100)
          color = if i < 5
                    "oklch(#{0.55 + (i * 0.06)} 0.12 240)"
                  else
                    "oklch(#{[0.78 + (i * 0.012), 0.95].min} 0.04 240)"
                  end
          { name: r[:name], total: r[:total], pct: pct, color: color }
        end
      end

      # Generate scatter plot data (approval vs depth)
      def scatter_data
        reviewers.select do |r|
          !r[:bot] && r[:approval_pct] && r[:actionable] && r[:actionable] >= 5
        end
      end

      # Calculate scatter plot coordinates
      def scatter_coords(approval_pct, depth_pct, total, max_total)
        w = 560
        h = 360
        p = 36

        x = p + ((approval_pct / 100.0) * (w - (2 * p)))
        y = h - p - (((depth_pct || 0) / 100.0) * (h - (2 * p)))
        radius = 4 + (Math.sqrt(total.to_f / max_total) * 14)

        { x: x.round(1), y: y.round(1), r: radius.round(1) }
      end

      # Check if point is in rubber-stamp zone
      def in_rubber_stamp_zone?(approval_pct, depth_pct)
        approval_pct >= 95 && (depth_pct || 0) < 15
      end

      # HTML escape helper
      def h(text)
        ERB::Util.html_escape(text.to_s)
      end

      # Get non-bot reviewers for depth table
      def depth_reviewers
        reviewers.reject do |r|
          r[:bot]
        end.select { |r| ((r[:minimal] || 0) + (r[:brief] || 0) + (r[:substantive] || 0)).positive? }
      end

      # Get reviewers with response time data
      def response_reviewers
        reviewers.reject { |r| r[:bot] }.select { |r| r[:response_initial] && (r[:response_n] || 0) >= 2 }
      end

      # Get reviewers with cross-squad data
      def cross_squad_reviewers
        reviewers.reject { |r| r[:bot] }.select { |r| r[:cross_squad_same] || r[:cross_squad_cross] }
      end

      # Get reviewers with ratio data
      def ratio_reviewers
        reviewers.reject { |r| r[:bot] }.select { |r| r[:prs_reviewed] || r[:prs_authored]&.positive? }
      end

      # Maximum ratio for scaling bar chart
      def max_ratio
        ratios = ratio_reviewers.map { |r| r[:ratio] }.compact
        ratios.empty? ? 100 : [ratios.max, 100].max
      end

      # Response time color based on hours
      def response_color(hours)
        return 'var(--ink-50)' if hours.nil?

        if hours < 1
          'var(--good)'
        elsif hours > 4
          'var(--bad)'
        else
          'var(--accent)'
        end
      end

      # Delta color for re-review comparison
      def delta_color(delta)
        return 'var(--ink-70)' if delta.nil?

        if delta > 3
          'var(--bad)'
        elsif delta < -1
          'var(--good)'
        else
          'var(--ink-70)'
        end
      end

      # Ratio bar color
      def ratio_bar_color(ratio)
        return 'var(--rule-2)' if ratio.nil?

        if ratio > 150
          'var(--accent)'
        elsif ratio < 50
          'var(--warn)'
        else
          'var(--rule-2)'
        end
      end

      # Ratio heatmap - 75-125% is green, outside that range progressively worse
      # Uses HeatmapColor with distance from sweet spot as the value
      def ratio_heatmap(ratio)
        return 'transparent' if ratio.nil?

        # Calculate distance from sweet spot (75-125%)
        distance = if ratio.between?(75, 125)
                     0 # In the sweet spot
                   elsif ratio < 75
                     75 - ratio # Distance below sweet spot
                   else
                     ratio - 125 # Distance above sweet spot
                   end

        # Use HeatmapColor: 0 distance = green, 75+ distance = red
        Calculators::HeatmapColor.compute(distance, min: 0, max: 75)
      end
    end
  end
end
