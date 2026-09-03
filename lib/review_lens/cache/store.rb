# frozen_string_literal: true

require 'fileutils'

begin
  require 'sqlite3'
rescue LoadError
  # sqlite3 is a native extension; a failed build shouldn't crash on require.
  # Store#new raises a clear CacheError instead.
  ReviewLens.const_set(:SQLITE3_LOAD_ERROR, true) unless defined?(ReviewLens::SQLITE3_LOAD_ERROR)
end

module ReviewLens
  module Cache
    # SQLite connection and schema.
    #
    # This is the tool's data store, not merely a cache: `fetch` writes PR and
    # review rows here, and reports read exclusively from it. Merged PRs are
    # immutable, so rows are never invalidated.
    class Store
      CURRENT_SCHEMA_VERSION = '1'

      attr_reader :db, :path

      def initialize(db_path:)
        assert_sqlite_available!
        @path = db_path
        ensure_directory_exists
        @db = SQLite3::Database.new(@path)
        @db.results_as_hash = true
        @db.busy_timeout = 5000
        apply_schema
      rescue SQLite3::Exception => e
        raise CacheError, "Could not open the database at #{@path}: #{e.message}"
      end

      # True when the store holds no pull requests yet.
      def empty?
        @db.get_first_value('SELECT COUNT(*) FROM github_pull_requests').to_i.zero?
      end

      def close
        @db.close if @db && !@db.closed?
      end

      private

      def assert_sqlite_available!
        return if defined?(SQLite3::Database)

        raise CacheError, <<~MSG.strip
          The sqlite3 gem could not be loaded, so review-lens cannot store data.
          Try: gem install sqlite3
        MSG
      end

      def ensure_directory_exists
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      rescue SystemCallError => e
        raise CacheError, "Could not create #{File.dirname(@path)}: #{e.message}"
      end

      def apply_schema
        @db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS github_pull_requests (
            repo          TEXT NOT NULL,
            pr_number     INTEGER NOT NULL,
            title         TEXT,
            author_login  TEXT,
            is_draft      INTEGER,
            created_at    TEXT,
            merged_at     TEXT,
            additions     INTEGER,
            deletions     INTEGER,
            changed_files INTEGER,
            cached_at     TEXT NOT NULL,
            PRIMARY KEY (repo, pr_number)
          );

          -- Every reviewer query filters on the PR's merged_at.
          CREATE INDEX IF NOT EXISTS idx_prs_repo_merged_at
            ON github_pull_requests(repo, merged_at);

          CREATE TABLE IF NOT EXISTS pr_reviews (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            repo            TEXT NOT NULL,
            pr_number       INTEGER NOT NULL,
            reviewer_login  TEXT,
            state           TEXT,
            submitted_at    TEXT,
            body            TEXT,
            FOREIGN KEY (repo, pr_number)
              REFERENCES github_pull_requests(repo, pr_number)
          );

          CREATE INDEX IF NOT EXISTS idx_pr_reviews_repo_pr
            ON pr_reviews(repo, pr_number);

          CREATE TABLE IF NOT EXISTS pr_review_requests (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            repo                TEXT NOT NULL,
            pr_number           INTEGER NOT NULL,
            requested_reviewer  TEXT NOT NULL,
            requested_at        TEXT NOT NULL,
            FOREIGN KEY (repo, pr_number)
              REFERENCES github_pull_requests(repo, pr_number)
          );

          CREATE INDEX IF NOT EXISTS idx_pr_review_requests_repo_pr
            ON pr_review_requests(repo, pr_number);

          CREATE INDEX IF NOT EXISTS idx_pr_review_requests_reviewer
            ON pr_review_requests(requested_reviewer);

          CREATE TABLE IF NOT EXISTS pr_commits (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            repo          TEXT NOT NULL,
            pr_number     INTEGER NOT NULL,
            sha           TEXT NOT NULL,
            author_login  TEXT,
            committed_at  TEXT NOT NULL,
            FOREIGN KEY (repo, pr_number)
              REFERENCES github_pull_requests(repo, pr_number)
          );

          CREATE INDEX IF NOT EXISTS idx_pr_commits_repo_pr
            ON pr_commits(repo, pr_number);
        SQL

        @db.execute(
          'INSERT INTO schema_meta (key, value) VALUES (?, ?) ' \
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          ['schema_version', CURRENT_SCHEMA_VERSION]
        )
      end
    end
  end
end
