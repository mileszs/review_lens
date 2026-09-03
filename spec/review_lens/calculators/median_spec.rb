# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Calculators::Median do
  it 'returns the middle value for an odd-sized set' do
    expect(described_class.call([3, 1, 2])).to eq(2)
  end

  it 'averages the two middle values for an even-sized set' do
    expect(described_class.call([1, 2, 3, 4])).to eq(2.5)
  end

  it 'is order independent' do
    expect(described_class.call([9, 1, 5])).to eq(described_class.call([1, 5, 9]))
  end

  it 'returns nil for an empty set' do
    expect(described_class.call([])).to be_nil
  end

  it 'returns nil for nil' do
    expect(described_class.call(nil)).to be_nil
  end

  it 'ignores nil entries' do
    expect(described_class.call([1, nil, 3])).to eq(2)
  end

  it 'handles a single value' do
    expect(described_class.call([7])).to eq(7)
  end
end
