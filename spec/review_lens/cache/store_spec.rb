# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe ReviewLens::Cache::Store do
  subject(:store) { described_class.new(db_path: ':memory:') }

  after { store.close }

  describe '#initialize' do
    it 'creates exactly the tables reviewer metrics need' do
      tables = store.db.execute("SELECT name FROM sqlite_master WHERE type='table'")
                    .map { |r| r['name'] }
                    .reject { |n| n.start_with?('sqlite_') }

      expect(tables).to match_array(
        %w[schema_meta github_pull_requests pr_reviews pr_review_requests pr_commits]
      )
    end

    it 'does not carry over unrelated domain tables' do
      tables = store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |r| r['name'] }

      expect(tables).not_to include('jira_issues', 'circleci_workflows', 'pr_files', 'pr_pickup_times')
    end

    it 'indexes merged_at, which every reviewer query filters on' do
      indexes = store.db.execute("SELECT name FROM sqlite_master WHERE type='index'").map { |r| r['name'] }

      expect(indexes).to include('idx_prs_repo_merged_at')
    end

    it 'records the schema version' do
      version = store.db.get_first_value("SELECT value FROM schema_meta WHERE key = 'schema_version'")

      expect(version).to eq(described_class::CURRENT_SCHEMA_VERSION)
    end
  end

  describe '#empty?' do
    it 'is true before anything is stored' do
      expect(store).to be_empty
    end

    it 'is false once a pull request exists' do
      store.db.execute(
        'INSERT INTO github_pull_requests (repo, pr_number, cached_at) VALUES (?, ?, ?)',
        ['acme/widgets', 1, Time.now.utc.iso8601]
      )

      expect(store).not_to be_empty
    end
  end

  describe 'with a file-based database' do
    it 'creates the containing directory when it does not exist' do
      Dir.mktmpdir do |tmp|
        path = File.join(tmp, 'nested', 'deeper', 'cache.db')
        file_store = described_class.new(db_path: path)

        expect(File.exist?(path)).to be true

        file_store.close
      end
    end
  end
end
