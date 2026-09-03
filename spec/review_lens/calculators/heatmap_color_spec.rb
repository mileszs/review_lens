# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::HeatmapColor do
  describe '.compute' do
    context 'with nil or invalid values' do
      it 'returns transparent for nil value' do
        expect(described_class.compute(nil, min: 0, max: 100)).to eq('transparent')
      end

      it 'returns transparent for NaN value' do
        expect(described_class.compute(Float::NAN, min: 0, max: 100)).to eq('transparent')
      end

      it 'returns transparent when min equals max' do
        expect(described_class.compute(50, min: 50, max: 50)).to eq('transparent')
      end
    end

    context 'with standard green-red ramp' do
      it 'returns green color at minimum (t=0)' do
        result = described_class.compute(0, min: 0, max: 100)
        # At t=0: hue=145, chroma=0.07, light=0.94
        expect(result).to eq('oklch(0.94 0.07 145)')
      end

      it 'returns amber color at midpoint (t=0.5)' do
        result = described_class.compute(50, min: 0, max: 100)
        # At t=0.5: hue=85, chroma=0.09, light=0.92
        expect(result).to eq('oklch(0.92 0.09 85)')
      end

      it 'returns red color at maximum (t=1)' do
        result = described_class.compute(100, min: 0, max: 100)
        # At t=1: hue=25, chroma=0.12, light=0.86
        expect(result).to eq('oklch(0.86 0.12 25)')
      end

      it 'clamps values below minimum' do
        result = described_class.compute(-10, min: 0, max: 100)
        expect(result).to eq('oklch(0.94 0.07 145)')
      end

      it 'clamps values above maximum' do
        result = described_class.compute(150, min: 0, max: 100)
        expect(result).to eq('oklch(0.86 0.12 25)')
      end
    end

    context 'with invert: true' do
      it 'returns red at minimum (inverted)' do
        result = described_class.compute(0, min: 0, max: 100, invert: true)
        # Inverted: t=1 at value=0
        expect(result).to eq('oklch(0.86 0.12 25)')
      end

      it 'returns green at maximum (inverted)' do
        result = described_class.compute(100, min: 0, max: 100, invert: true)
        # Inverted: t=0 at value=100
        expect(result).to eq('oklch(0.94 0.07 145)')
      end
    end

    context 'with neutral: true (blue ramp)' do
      it 'returns light blue at minimum' do
        result = described_class.compute(0, min: 0, max: 100, neutral: true)
        # l = 0.97 - 0.12 * 0 = 0.97
        expect(result).to eq('oklch(0.97 0.05 240)')
      end

      it 'returns darker blue at maximum' do
        result = described_class.compute(100, min: 0, max: 100, neutral: true)
        # l = 0.97 - 0.12 * 1 = 0.85
        expect(result).to eq('oklch(0.85 0.05 240)')
      end

      it 'returns mid blue at midpoint' do
        result = described_class.compute(50, min: 0, max: 100, neutral: true)
        # l = 0.97 - 0.12 * 0.5 = 0.91
        expect(result).to eq('oklch(0.91 0.05 240)')
      end
    end

    context 'with real-world approval rate values' do
      # Based on data.js: approval rates range from ~73% to 100%
      it 'shows green for moderate approval rate' do
        result = described_class.compute(73.6, min: 70, max: 100)
        # Low t value = green-ish (hue between 85-145)
        expect(result).to match(/oklch\(0\.9\d+ 0\.0\d+ \d+\)/)
      end

      it 'shows red for 100% approval rate (rubber-stamp territory)' do
        result = described_class.compute(100, min: 70, max: 100)
        expect(result).to eq('oklch(0.86 0.12 25)')
      end
    end
  end
end
