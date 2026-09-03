# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReviewLens::Analysis::CrossTeam do
  def config(teams)
    ReviewLens::Configuration.new(repo: 'acme/widgets', config_path: '/nonexistent', teams: teams)
  end

  subject(:result) { described_class.new(config(teams)).call(pairs) }

  let(:teams) { { 'platform' => %w[alice bob], 'product' => %w[carol] } }
  let(:pairs) do
    [
      { reviewer_login: 'alice', author_login: 'bob', count: 4 },    # same team
      { reviewer_login: 'alice', author_login: 'carol', count: 6 },  # cross team
      { reviewer_login: 'alice', author_login: 'zoe', count: 5 }     # unknown -> external
    ]
  end

  it 'separates same-team, cross-team and external reviews' do
    expect(result[:same_squad_reviews]).to eq(4)
    expect(result[:cross_squad_reviews]).to eq(6)
    expect(result[:external_reviews]).to eq(5)
  end

  it 'excludes external reviews from the rate, since their team is unknown' do
    expect(result[:cross_squad_rate]).to eq(60.0) # 6 of 10 known
  end

  it 'breaks the same figures down per reviewer' do
    alice = result[:reviewer_stats].find { |s| s[:reviewer_login] == 'alice' }

    expect(alice).to include(same_squad: 4, cross_squad: 6, external: 5, cross_squad_rate: 60.0)
  end

  # Teams are optional. Without them this metric is meaningless, and reporting
  # zeroes would read as "nobody reviews outside their team".
  context 'when no teams are configured' do
    it 'returns nil so the section can be omitted' do
      expect(described_class.new(config({})).call(pairs)).to be_nil
    end

    it 'returns nil for a map of empty teams' do
      expect(described_class.new(config({ 'a' => nil })).call(pairs)).to be_nil
    end
  end

  it 'returns nil with no review pairs' do
    expect(described_class.new(config(teams)).call([])).to be_nil
  end

  it 'reports a zero rate when every known review is within one team' do
    only_same = [{ reviewer_login: 'alice', author_login: 'bob', count: 3 }]

    expect(described_class.new(config(teams)).call(only_same)[:cross_squad_rate]).to eq(0)
  end
end
