# frozen_string_literal: true

require_relative 'lib/review_lens/version'

Gem::Specification.new do |spec|
  spec.name          = 'review_lens'
  spec.version       = ReviewLens::VERSION
  spec.authors       = ['Miles Z. Sterrett']
  spec.email         = ['miles@mileszs.com']

  spec.summary       = 'Humane code review metrics, including private per-reviewer reports.'
  spec.description   = <<~DESC
    Analyzes GitHub pull request reviews and produces a team dashboard plus a
    private, per-person report you can share with one individual. Individual
    reports never name anyone else: peers appear only as unlabeled points in a
    distribution, and comparisons are direction-aware rather than ranked.
  DESC
  spec.homepage      = 'https://github.com/mileszs/review_lens'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri']     = spec.homepage
  spec.metadata['source_code_uri']  = "#{spec.homepage}/tree/main"
  spec.metadata['changelog_uri']    = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri']  = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/**/*.rb',
    'lib/**/templates/**/*',
    'exe/*',
    'README.md',
    'LICENSE',
    'CHANGELOG.md'
  ]
  spec.bindir      = 'exe'
  spec.executables = ['review-lens']
  spec.require_paths = ['lib']

  spec.add_dependency 'sqlite3', '~> 2.0'
  spec.add_dependency 'tzinfo', '~> 2.0'
  spec.add_dependency 'tzinfo-data', '~> 1.2024'
end
