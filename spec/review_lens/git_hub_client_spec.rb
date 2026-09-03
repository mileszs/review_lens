# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'support/fake_executor'

RSpec.describe ReviewLens::GitHubClient do
  def ok(body) = FakeExecutor.ok(body)
  def fail_with(err) = FakeExecutor.failure(err)

  subject(:client) { described_class.new('acme/widgets', executor: executor) }

  let(:executor) { FakeExecutor.new }

  describe '#initialize' do
    it 'refuses to build without a repo' do
      expect { described_class.new('') }.to raise_error(ReviewLens::ConfigurationError, /repo is required/)
    end
  end

  # The upstream tool warned and returned [] here, which silently produced an
  # empty report. A first-time user must get a real error instead.
  describe 'failure handling' do
    it 'raises a helpful error when gh is not installed' do
      allow(executor).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { client.ensure_available! }
        .to raise_error(ReviewLens::GitHubCliError, /not found on your PATH/)
    end

    it 'raises a helpful error when gh is not authenticated' do
      executor = FakeExecutor.new([fail_with('You are not logged into any GitHub hosts')])
      client = described_class.new('acme/widgets', executor: executor)

      expect { client.ensure_available! }
        .to raise_error(ReviewLens::GitHubCliError, /gh auth login/)
    end

    it 'raises rather than returning empty results when a query fails' do
      executor = FakeExecutor.new([fail_with('boom')])
      client = described_class.new('acme/widgets', executor: executor)

      expect { client.fetch_pr_commits(1) }.to raise_error(ReviewLens::GitHubCliError, /failed/)
    end

    it 'raises a clear error on unparseable output' do
      executor = FakeExecutor.new([ok('not json')])
      client = described_class.new('acme/widgets', executor: executor)

      expect { client.fetch_pr_commits(1) }.to raise_error(ReviewLens::GitHubCliError, /Could not parse/)
    end

    it 'treats empty output as no results rather than an error' do
      executor = FakeExecutor.new([ok('')])
      client = described_class.new('acme/widgets', executor: executor)

      expect(client.fetch_pr_events(1)).to eq([])
    end
  end

  describe '#fetch_merged_prs' do
    let(:since) { Time.utc(2026, 1, 1) }
    let(:until_time) { Time.utc(2026, 4, 1) }

    it 'queries merged PRs on the base branch within the window' do
      executor = FakeExecutor.new([ok('[{"number":1}]')])
      described_class.new('acme/widgets', executor: executor)
                     .fetch_merged_prs(base_branch: 'main', since: since, until_time: until_time)

      cmd = executor.commands.first
      expect(cmd.first(3)).to eq(%w[gh pr list])
      expect(cmd).to include('--repo', 'acme/widgets', '--state', 'merged', '--base', 'main')
      expect(cmd.join(' ')).to include('merged:2026-01-01T00:00:00Z..2026-04-01T00:00:00Z')
    end

    it 'returns the parsed rows' do
      executor = FakeExecutor.new([ok('[{"number":7,"title":"Fix"}]')])
      result = described_class.new('acme/widgets', executor: executor)
                              .fetch_merged_prs(base_branch: 'main', since: since, until_time: until_time)

      expect(result).to eq([{ 'number' => 7, 'title' => 'Fix' }])
    end

    # `gh pr list` caps at 1000 with no page flag, so a full page means there
    # are probably more; split the window instead of silently truncating.
    context 'when a page comes back at the limit' do
      it 'splits the window and merges the halves' do
        full_page = ok((1..described_class::PAGE_LIMIT).map { |n| { number: n } }.to_json)
        executor = FakeExecutor.new([full_page, ok('[{"number":2001}]'), ok('[{"number":2002}]')])

        result = described_class.new('acme/widgets', executor: executor)
                                .fetch_merged_prs(base_branch: 'main', since: since, until_time: until_time)

        expect(executor.commands.length).to eq(3)
        expect(result.map { |r| r['number'] }).to include(2001, 2002)
      end

      it 'deduplicates PRs appearing in both halves' do
        full_page = ok((1..described_class::PAGE_LIMIT).map { |n| { number: n } }.to_json)
        dup = ok('[{"number":42}]')
        executor = FakeExecutor.new([full_page, dup, dup])

        result = described_class.new('acme/widgets', executor: executor)
                                .fetch_merged_prs(base_branch: 'main', since: since, until_time: until_time)

        expect(result.count { |r| r['number'] == 42 }).to eq(1)
      end

      it 'stops subdividing once the window is very small' do
        full_page = ok((1..described_class::PAGE_LIMIT).map { |n| { number: n } }.to_json)
        executor = FakeExecutor.new([full_page])

        result = described_class.new('acme/widgets', executor: executor).fetch_merged_prs(
          base_branch: 'main', since: since, until_time: since + 60
        )

        expect(executor.commands.length).to eq(1)
        expect(result.length).to eq(described_class::PAGE_LIMIT)
      end
    end
  end

  describe '#extract_review_requests' do
    it 'keeps individual review requests' do
      events = [
        { 'event' => 'review_requested', 'created_at' => '2026-01-02T10:00:00Z',
          'requested_reviewer' => { 'login' => 'alice' } },
        { 'event' => 'labeled', 'created_at' => '2026-01-02T11:00:00Z' }
      ]

      expect(client.extract_review_requests(events)).to eq(
        [{ requested_reviewer: 'alice', requested_at: '2026-01-02T10:00:00Z' }]
      )
    end

    it 'skips team requests, which have no individual login' do
      events = [{ 'event' => 'review_requested', 'requested_team' => { 'name' => 'platform' } }]

      expect(client.extract_review_requests(events)).to eq([])
    end

    it 'handles nil safely' do
      expect(client.extract_review_requests(nil)).to eq([])
    end
  end

  describe '#fetch_pr_commits' do
    it 'flattens the API shape into sha/author/date' do
      body = [{ 'sha' => 'abc', 'author' => { 'login' => 'alice' },
                'commit' => { 'author' => { 'date' => '2026-01-03T09:00:00Z' } } }].to_json
      executor = FakeExecutor.new([ok(body)])

      result = described_class.new('acme/widgets', executor: executor).fetch_pr_commits(5)

      expect(result).to eq([{ sha: 'abc', author_login: 'alice', committed_at: '2026-01-03T09:00:00Z' }])
    end

    it 'paginates the REST API' do
      executor = FakeExecutor.new([ok('[]')])
      described_class.new('acme/widgets', executor: executor).fetch_pr_commits(5)

      expect(executor.commands.first).to include('--paginate')
    end
  end
end
