# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe ReviewLens::Configuration do
  def config(**overrides)
    described_class.new(config_path: '/nonexistent/.review-lens.yml', **overrides)
  end

  describe 'defaults' do
    it 'boots with no config file and no team map' do
      expect { config }.not_to raise_error
    end

    it 'defaults the window, branch and output directory' do
      cfg = config
      expect(cfg.days).to eq(90)
      expect(cfg.base_branch).to eq('main')
      expect(cfg.output_dir).to eq('review-lens')
    end

    it 'stores the database under the user home, not the working directory' do
      expect(config.cache_db_path).to eq(File.join(Dir.home, '.review-lens', 'cache.db'))
    end

    it 'leaves evaluative flags off' do
      expect(config.show_flags).to be false
    end
  end

  describe 'file loading' do
    it 'reads settings from a config file' do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, '.review-lens.yml')
        File.write(path, { 'repo' => 'acme/widgets', 'days' => 30, 'show_flags' => true }.to_yaml)

        cfg = described_class.new(config_path: path)

        expect(cfg.repo).to eq('acme/widgets')
        expect(cfg.days).to eq(30)
        expect(cfg.show_flags).to be true
      end
    end

    it 'ignores an unreadable config file rather than crashing' do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, '.review-lens.yml')
        File.write(path, "\tnot: [valid yaml")

        expect { described_class.new(config_path: path) }.not_to raise_error
      end
    end

    it 'lets an explicit value win over the file' do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, '.review-lens.yml')
        File.write(path, { 'repo' => 'from/file' }.to_yaml)

        expect(described_class.new(config_path: path, repo: 'from/flag').repo).to eq('from/flag')
      end
    end
  end

  describe '#bot?' do
    it 'matches known bot logins exactly' do
      expect(config.bot?('dependabot')).to be true
      expect(config.bot?('github-actions')).to be true
    end

    it 'matches any login with a [bot] suffix' do
      expect(config.bot?('some-new-tool[bot]')).to be true
    end

    # Real bots often extend a known name, e.g. GitHub's
    # "copilot-pull-request-reviewer".
    it 'matches a known bot name followed by a separator' do
      expect(config.bot?('copilot-pull-request-reviewer')).to be true
      expect(config.bot?('cursor-agent')).to be true
    end

    it 'is case insensitive' do
      expect(config.bot?('Dependabot')).to be true
    end

    # A bare substring match (what the upstream tool used) would flag any login
    # containing a bot name.
    it 'does not flag a human whose login merely contains a bot name' do
      expect(config.bot?('precursor')).to be false
      expect(config.bot?('copilotson')).to be false
      expect(config.bot?('dependabotany')).to be false
    end

    it 'accepts extra bot logins from config' do
      expect(config(bot_logins: %w[housekeeper]).bot?('housekeeper')).to be true
    end
  end

  describe 'teams' do
    let(:teams) { { 'platform' => %w[alice bob], 'product' => %w[carol] } }

    it 'reports no teams by default' do
      expect(config.teams?).to be false
    end

    it 'maps a login to its team' do
      expect(config(teams: teams).team_for('alice')).to eq('platform')
    end

    it 'is case insensitive on logins' do
      expect(config(teams: teams).team_for('ALICE')).to eq('platform')
    end

    it 'returns nil for an unknown login' do
      expect(config(teams: teams).team_for('zoe')).to be_nil
    end

    # A team key with no members parses as nil in YAML, which used to crash on
    # `members.include?`.
    it 'survives a team declared with no members' do
      cfg = config(teams: { 'platform' => %w[alice], 'newteam' => nil })

      expect { cfg.team_for('alice') }.not_to raise_error
      expect(cfg.team_for('alice')).to eq('platform')
    end

    it 'treats a map of only empty teams as no teams' do
      expect(config(teams: { 'a' => nil, 'b' => [] }).teams?).to be false
    end
  end
end
