# frozen_string_literal: true

require_relative 'review_lens/version'
require_relative 'review_lens/errors'
require_relative 'review_lens/configuration'
require_relative 'review_lens/date_range'
require_relative 'review_lens/github_client'

require_relative 'review_lens/calculators/median'
require_relative 'review_lens/calculators/business_hours'
require_relative 'review_lens/calculators/review_distribution'
require_relative 'review_lens/calculators/reviewer_percentiles'
require_relative 'review_lens/calculators/reviewer_flags'
require_relative 'review_lens/calculators/heatmap_color'

require_relative 'review_lens/models/reviewer_stats'
require_relative 'review_lens/models/reviewer_response_time'

require_relative 'review_lens/cache/store'
require_relative 'review_lens/cache/github_cache'
require_relative 'review_lens/ingest'

require_relative 'review_lens/analysis/cross_team'
require_relative 'review_lens/analysis/response_times'
require_relative 'review_lens/analysis/effectiveness'
require_relative 'review_lens/analyzer'

require_relative 'review_lens/presentation/anonymizer'
require_relative 'review_lens/presentation/watch_list'
require_relative 'review_lens/presentation/data_mapper'
require_relative 'review_lens/presentation/team_report'
require_relative 'review_lens/presentation/individual_report'
require_relative 'review_lens/cli'

# Humane code review metrics from GitHub pull request data.
module ReviewLens
end
