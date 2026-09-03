# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe ReviewLens::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run(*argv)
    status = described_class.new(stdout: out, stderr: err).run(argv)
    [status, out.string, err.string]
  end

  around do |example|
    Dir.mktmpdir { |tmp| Dir.chdir(tmp) { example.run } }
  end

  describe 'help and version' do
    it 'prints the version' do
      status, stdout, = run('version')

      expect(status).to eq(0)
      expect(stdout).to include(ReviewLens::VERSION)
    end

    it 'shows usage when given no command' do
      _, stdout, = run

      expect(stdout).to include('review-lens fetch', 'review-lens report')
    end

    it 'explains that individual reports are private' do
      _, stdout, = run

      expect(stdout).to match(/private|not meant to be published/i)
    end
  end

  describe 'error handling' do
    it 'exits non-zero with a clear message when no repo is given' do
      status, _, stderr = run('fetch')

      expect(status).to eq(1)
      expect(stderr).to include('--repo owner/name')
    end

    it 'does not print a stack trace' do
      _, _, stderr = run('fetch')

      expect(stderr).not_to include('.rb:')
    end

    # Reporting before fetching used to yield an empty-looking report.
    it 'tells the user to fetch first when the store is empty' do
      status, _, stderr = run('report', '--repo', 'acme/widgets', '--db', File.join(Dir.pwd, 'cache.db'))

      expect(status).to eq(1)
      expect(stderr).to include('review-lens fetch')
    end
  end

  describe 'report output' do
    let(:db) { File.join(Dir.pwd, 'cache.db') }

    before do
      store = ReviewLens::Cache::Store.new(db_path: db)
      store.db.execute(
        'INSERT INTO github_pull_requests (repo, pr_number, title, author_login, merged_at, cached_at) ' \
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['acme/widgets', 1, 'PR', 'carol', '2026-02-01T12:00:00Z', Time.now.utc.iso8601]
      )
      store.db.execute(
        'INSERT INTO pr_reviews (repo, pr_number, reviewer_login, state, submitted_at, body) ' \
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['acme/widgets', 1, 'alice', 'APPROVED', '2026-02-01T11:00:00Z', 'x' * 150]
      )
      store.close
    end

    def report(*extra)
      run('report', '--repo', 'acme/widgets', '--db', db,
          '--since', '2026-01-01', '--until', '2026-04-01', '--out', 'output', *extra)
    end

    it 'writes a team dashboard and per-person reports' do
      status, stdout, = report

      expect(status).to eq(0)
      expect(File.exist?('output/team.html')).to be true
      expect(File.exist?('output/reviewers/alice.html')).to be true
      expect(stdout).to include('team dashboard')
    end

    it 'reminds the user that individual reports are per-person' do
      _, stdout, = report

      expect(stdout).to match(/Share each person only their own/i)
    end

    # These files name individuals; they should not land in a repo by accident.
    it 'drops a .gitignore beside the individual reports' do
      report

      expect(File.read('output/reviewers/.gitignore')).to eq("*\n")
    end

    it 'can build only one person with --login' do
      report('--login', 'alice')

      expect(Dir['output/reviewers/*.html'].map { |f| File.basename(f) }).to eq(['alice.html'])
    end

    it 'can skip the individual reports' do
      report('--no-individual')

      expect(File.exist?('output/team.html')).to be true
      expect(Dir.exist?('output/reviewers')).to be false
    end

    it 'can skip the team dashboard' do
      report('--no-team')

      expect(File.exist?('output/team.html')).to be false
      expect(File.exist?('output/reviewers/alice.html')).to be true
    end

    it 'writes an anonymized team report on request' do
      report('--anonymize')

      expect(File.exist?('output/team-anonymized.html')).to be true
    end
  end
end
