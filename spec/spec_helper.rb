# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift __dir__
require 'review_lens'

# Builds a Configuration isolated from any real .review-lens.yml on this machine.
module ConfigBuilder
  def build_config(**overrides)
    ReviewLens::Configuration.new(
      repo: 'acme/widgets', config_path: '/nonexistent/.review-lens.yml', **overrides
    )
  end
end

RSpec.configure do |config|
  config.include ConfigBuilder
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = false
  config.default_formatter = 'doc' if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  # Deliberately NOT silencing $stdout/$stderr suite-wide: the upstream project
  # did, which hid the warn-based failure path that this gem now raises on.

  # Never let a spec shell out to the real `gh`.
  config.before do
    allow(Open3).to receive(:capture3).and_raise(
      'Specs must not invoke the real gh CLI -- inject a fake executor.'
    )
  end
end
