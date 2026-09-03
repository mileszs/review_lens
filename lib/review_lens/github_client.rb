# frozen_string_literal: true

require 'json'
require 'open3'

module ReviewLens
  # Wrapper around the `gh` CLI, which supplies both data and authentication.
  #
  # Two deliberate differences from a naive wrapper:
  #
  # 1. Failures raise. A missing or unauthenticated `gh` used to warn and
  #    return [], which silently produced an empty report -- the worst possible
  #    outcome for someone running this for the first time.
  # 2. `gh pr list` caps at 1000 results with no page flag, so a busy repo over
  #    a long window would silently truncate. When a window comes back at the
  #    cap we split it in half and recurse.
  class GitHubClient
    PAGE_LIMIT = 1000
    MIN_SPLIT_SECONDS = 3600 # don't subdivide below an hour

    LIST_FIELDS = 'number,title,createdAt,mergedAt,author,reviews'

    def initialize(repo, executor: Open3)
      raise ConfigurationError, 'repo is required (owner/name)' if repo.to_s.empty?

      @repo = repo
      @executor = executor
    end

    # Verifies `gh` is installed and authenticated. Call once before a fetch so
    # the user gets one clear error instead of N confusing empty results.
    def ensure_available!
      _, err, status = capture('gh', 'auth', 'status')
      return true if status.success?

      raise GitHubCliError, <<~MSG.strip
        GitHub CLI is not authenticated (`gh auth status` failed).
        Run: gh auth login
        #{err.to_s.strip}
      MSG
    rescue Errno::ENOENT
      raise GitHubCliError, <<~MSG.strip
        GitHub CLI (`gh`) was not found on your PATH.
        Install it from https://cli.github.com and run `gh auth login`.
      MSG
    end

    # Merged PRs in [since, until_time], with their reviews.
    # Splits the window when a page comes back at the cap.
    def fetch_merged_prs(base_branch:, since:, until_time:)
      rows = list_merged(base_branch, since, until_time)
      return rows if rows.length < PAGE_LIMIT
      return rows if (until_time - since) <= MIN_SPLIT_SECONDS

      mid = since + ((until_time - since) / 2)
      first = fetch_merged_prs(base_branch: base_branch, since: since, until_time: mid)
      second = fetch_merged_prs(base_branch: base_branch, since: mid, until_time: until_time)
      (first + second).uniq { |pr| pr['number'] }
    end

    def fetch_pr_details(pr_number)
      json(
        'gh', 'pr', 'view', pr_number.to_s, '--repo', @repo,
        '--json', 'number,title,author,createdAt,mergedAt,isDraft,additions,deletions,changedFiles,reviews'
      )
    end

    # PRs are issues in GitHub's REST API, so review requests come from issue events.
    def fetch_pr_events(pr_number)
      json('gh', 'api', '--paginate', "repos/#{@repo}/issues/#{pr_number}/events") || []
    end

    def fetch_pr_commits(pr_number)
      commits = json('gh', 'api', '--paginate', "repos/#{@repo}/pulls/#{pr_number}/commits") || []
      commits.map do |commit|
        {
          sha: commit['sha'],
          author_login: commit.dig('author', 'login'),
          committed_at: commit.dig('commit', 'author', 'date')
        }
      end
    end

    # review_requested events -> [{ requested_reviewer:, requested_at: }]
    # Team-level requests have no login and are skipped.
    def extract_review_requests(events)
      Array(events)
        .select { |e| e['event'] == 'review_requested' }
        .filter_map do |event|
          reviewer = event.dig('requested_reviewer', 'login')
          next unless reviewer

          { requested_reviewer: reviewer, requested_at: event['created_at'] }
        end
    end

    def self.format_datetime(time)
      time.getutc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end

    private

    def list_merged(base_branch, since, until_time)
      search = "merged:#{self.class.format_datetime(since)}..#{self.class.format_datetime(until_time)}"
      json(
        'gh', 'pr', 'list', '--repo', @repo,
        '--state', 'merged', '--base', base_branch,
        '--search', search, '--json', LIST_FIELDS,
        '--limit', PAGE_LIMIT.to_s
      ) || []
    end

    def json(*cmd)
      out, err, status = capture(*cmd)
      raise GitHubCliError, "`#{cmd.take(3).join(' ')}` failed: #{err.to_s.strip}" unless status.success?

      body = out.to_s.dup.force_encoding('UTF-8')
      return nil if body.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise GitHubCliError, "Could not parse GitHub CLI output: #{e.message}"
    end

    def capture(*cmd)
      @executor.capture3(*cmd)
    rescue Errno::ENOENT
      raise GitHubCliError, 'GitHub CLI (`gh`) was not found on your PATH. See https://cli.github.com'
    end
  end
end
