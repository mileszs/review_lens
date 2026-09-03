# frozen_string_literal: true

module ReviewLens
  module Calculators
    # Computes oklch heatmap colors for data visualization.
    # Port of viz.jsx heatColor() function (lines 6-32).
    #
    # Uses a three-stop perceptual ramp in oklch color space:
    # - Good (green, hue 145) -> Mid (amber, hue 85) -> Bad (red, hue 25)
    # - Neutral mode uses a single-hue blue ramp
    module HeatmapColor
      module_function

      # Compute an oklch CSS color string for a value in a range.
      #
      # @param value [Numeric, nil] The value to map to a color
      # @param min [Numeric] The minimum value in the range
      # @param max [Numeric] The maximum value in the range
      # @param invert [Boolean] If true, lower values are "bad" (red)
      # @param neutral [Boolean] If true, use single-hue blue ramp instead of green-red
      # @return [String] CSS color string like "oklch(0.92 0.09 85)"
      def compute(value, min:, max:, invert: false, neutral: false)
        return 'transparent' if value.nil? || (value.is_a?(Float) && value.nan?)
        return 'transparent' if max == min # Avoid division by zero

        # Normalize to [0, 1]
        t0 = (value - min).to_f / (max - min)
        t = [[invert ? 1 - t0 : t0, 0].max, 1].min

        if neutral
          # Single-hue blue ramp
          l = 0.97 - (0.12 * t)
          return "oklch(#{l.round(3)} 0.05 240)"
        end

        # Three-stop ramp: green -> amber -> red
        if t < 0.5
          # Green (145) -> Amber (85)
          u = t / 0.5
          hue = 145 - (60 * u)
          chroma = 0.07 + (0.02 * u)
          light = 0.94 - (0.02 * u)
        else
          # Amber (85) -> Red (25)
          u = (t - 0.5) / 0.5
          hue = 85 - (60 * u)
          chroma = 0.09 + (0.03 * u)
          light = 0.92 - (0.06 * u)
        end

        "oklch(#{light.round(3)} #{chroma.round(3)} #{hue.round(0)})"
      end
    end
  end
end
