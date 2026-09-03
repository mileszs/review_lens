# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::ReviewDistribution do
  describe '#gini_coefficient' do
    it 'returns 0 for perfectly equal distribution' do
      calc = described_class.new([10, 10, 10, 10])
      expect(calc.gini_coefficient).to eq(0)
    end

    it 'returns close to 1 for highly unequal distribution' do
      calc = described_class.new([100, 1, 1, 1])
      expect(calc.gini_coefficient).to be > 0.7
    end

    it 'returns 0 for single reviewer' do
      calc = described_class.new([50])
      expect(calc.gini_coefficient).to eq(0)
    end

    it 'returns 0 for empty input' do
      calc = described_class.new([])
      expect(calc.gini_coefficient).to eq(0)
    end
  end

  describe '#bus_factor' do
    it 'returns 1 when top reviewer has >50% of reviews' do
      calc = described_class.new([60, 20, 20])
      expect(calc.bus_factor).to eq(1)
    end

    it 'returns 2 when top 2 reviewers cover >50%' do
      calc = described_class.new([30, 25, 25, 20])
      expect(calc.bus_factor).to eq(2)
    end

    it 'returns 3 when top 3 reviewers needed for >50%' do
      calc = described_class.new([20, 20, 15, 15, 15, 15])
      expect(calc.bus_factor).to eq(3)
    end

    it 'returns 0 for empty input' do
      calc = described_class.new([])
      expect(calc.bus_factor).to eq(0)
    end
  end

  describe '#top_reviewer_share' do
    it 'calculates percentage of top reviewer' do
      calc = described_class.new([50, 30, 20])
      expect(calc.top_reviewer_share).to eq(50.0)
    end

    it 'returns 0 for empty input' do
      calc = described_class.new([])
      expect(calc.top_reviewer_share).to eq(0)
    end
  end

  describe '#top_n_share' do
    it 'calculates percentage of top N reviewers' do
      calc = described_class.new([40, 30, 20, 10])
      expect(calc.top_n_share(2)).to eq(70.0)
      expect(calc.top_n_share(3)).to eq(90.0)
    end

    it 'handles N larger than reviewer count' do
      calc = described_class.new([60, 40])
      expect(calc.top_n_share(5)).to eq(100.0)
    end
  end

  describe '#health_rating' do
    it 'returns :good for well-distributed reviews' do
      # Low gini (< 0.3) and bus factor >= 3
      # Need 6 reviewers so that top 3 cover just over 50%
      calc = described_class.new([20, 18, 17, 15, 15, 15])
      expect(calc.health_rating).to eq(:good)
    end

    it 'returns :moderate for somewhat concentrated reviews' do
      # Gini 0.3-0.5, bus factor >= 2
      calc = described_class.new([40, 30, 20, 10])
      expect(calc.health_rating).to eq(:moderate)
    end

    it 'returns :concentrated for highly concentrated reviews' do
      # High gini or low bus factor
      calc = described_class.new([80, 10, 5, 5])
      expect(calc.health_rating).to eq(:concentrated)
    end
  end
end
