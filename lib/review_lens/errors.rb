# frozen_string_literal: true

module ReviewLens
  class Error < StandardError
  end

  # `gh` is missing, too old, or not authenticated.
  class GitHubCliError < Error
  end

  # The cache database is missing, unreadable, or sqlite3 failed to load.
  class CacheError < Error
  end

  # Raised when a report is requested before any data has been fetched.
  class NoDataError < Error
  end

  class ConfigurationError < Error
  end
end
