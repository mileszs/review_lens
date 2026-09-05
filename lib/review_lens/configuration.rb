# frozen_string_literal: true

require 'yaml'

module ReviewLens
  # All tunable settings for a run.
  #
  # Precedence, highest first: explicit keyword/CLI value, then ENV, then the
  # config file (`.review-lens.yml`), then the defaults below.
  #
  # Unlike a typical app config this must NEVER raise for a missing file or a
  # missing team map -- a first-time user has neither.
  class Configuration
    CONFIG_FILENAME = '.review-lens.yml'

    # Bot logins, matched case-insensitively. A login counts as a bot when it
    # equals one of these, or begins with one followed by "-" or "[".
    #
    # Deliberately not a bare substring match (which would misclassify a human
    # login like "precursor") and deliberately not an exact match either, since
    # real bots appear as e.g. "copilot-pull-request-reviewer".
    DEFAULT_BOT_LOGINS = %w[
      github-actions copilot cursor dependabot renovate
      snyk sonarcloud codecov coderabbitai greenkeeper
    ].freeze

    # Review depth is bucketed by comment length in characters.
    DEFAULT_MINIMAL_THRESHOLD = 10
    DEFAULT_SUBSTANTIVE_THRESHOLD = 100

    # A reviewer needs at least this much activity before we compare them to
    # the team. Small samples produce confident-looking nonsense.
    DEFAULT_MIN_SAMPLE = 5

    # Config-file keys map 1:1 onto attributes; the value is how to coerce.
    FILE_FIELDS = {
      'repo' => :string, 'base_branch' => :string, 'timezone' => :string,
      'output_dir' => :string, 'teams' => :raw,
      'cache_db_path' => :path,
      'days' => :integer, 'business_start_hour' => :integer, 'business_end_hour' => :integer,
      'minimal_threshold' => :integer, 'substantive_threshold' => :integer, 'min_sample' => :integer,
      'show_flags' => :boolean,
      'bot_logins' => :downcased_list, 'anonymous_names' => :list
    }.freeze

    COERCIONS = {
      integer: lambda(&:to_i),
      boolean: ->(v) { !v.nil? && v != false },
      list: ->(v) { Array(v) },
      downcased_list: ->(v) { Array(v).map { |x| x.to_s.downcase } },
      path: ->(v) { File.expand_path(v) }
    }.freeze

    attr_accessor :repo, :base_branch, :cache_db_path, :fresh, :days,
                  :teams, :bot_logins, :timezone,
                  :business_start_hour, :business_end_hour,
                  :minimal_threshold, :substantive_threshold, :min_sample,
                  :show_flags, :output_dir, :anonymous_names

    def initialize(**overrides)
      file = load_config_file(overrides[:config_path])
      apply_defaults
      apply_file(file)
      apply_env
      overrides.each { |k, v| public_send(:"#{k}=", v) unless v.nil? || k == :config_path }
      normalize!
    end

    # Does this login belong to a bot?
    def bot?(login)
      name = login.to_s.downcase
      return true if name.end_with?('[bot]')

      stem = name.sub(/\[bot\]\z/, '')
      bot_logins.any? { |pattern| bot_match?(stem, pattern) }
    end

    # login -> team name, or nil when unknown / no team map configured.
    def team_for(login)
      return nil if teams.nil? || teams.empty?

      teams.each do |team, members|
        # A team declared with no members parses as nil -- guard it.
        return team if Array(members).any? { |m| m.to_s.casecmp?(login.to_s) }
      end
      nil
    end

    def bot_match?(login, pattern)
      login == pattern || login.start_with?("#{pattern}-", "#{pattern}[")
    end

    def teams?
      !(teams.nil? || teams.empty? || teams.values.all? { |m| Array(m).empty? })
    end

    def fresh? = !!fresh

    private

    def apply_defaults
      @repo = nil
      @base_branch = 'main'
      @cache_db_path = File.join(Dir.home, '.review-lens', 'cache.db')
      @fresh = false
      @days = 90
      @teams = {}
      @bot_logins = DEFAULT_BOT_LOGINS.dup
      @timezone = 'America/New_York'
      @business_start_hour = 8
      @business_end_hour = 18
      @minimal_threshold = DEFAULT_MINIMAL_THRESHOLD
      @substantive_threshold = DEFAULT_SUBSTANTIVE_THRESHOLD
      @min_sample = DEFAULT_MIN_SAMPLE
      @show_flags = false
      @output_dir = 'review-lens'
      @anonymous_names = nil
    end

    def apply_file(data)
      return if data.nil? || data.empty?

      FILE_FIELDS.each do |key, coercion|
        next if data[key].nil?

        instance_variable_set(:"@#{key}", coerce(data[key], coercion))
      end
    end

    def coerce(value, coercion)
      COERCIONS.key?(coercion) ? COERCIONS[coercion].call(value) : value
    end

    def apply_env
      @repo = ENV['REVIEW_LENS_REPO'] if ENV['REVIEW_LENS_REPO']
      @cache_db_path = File.expand_path(ENV['REVIEW_LENS_DB']) if ENV['REVIEW_LENS_DB']
      @fresh = true if ENV['FRESH'] == 'true'
      @timezone = ENV['REVIEW_LENS_TZ'] if ENV['REVIEW_LENS_TZ']
    end

    # Returns {} rather than raising when the file is absent or unreadable --
    # a first run has no config file and must still work.
    #
    # Pass `config_path: false` to skip the file entirely. Host applications
    # that build a Configuration themselves need that, so a stray
    # .review-lens.yml on a developer's machine cannot override them.
    def load_config_file(explicit_path)
      return {} if explicit_path == false

      path = explicit_path || find_config_file
      return {} unless path && File.readable?(path)

      YAML.safe_load_file(path) || {}
    rescue StandardError => e
      warn "review-lens: ignoring unreadable #{path}: #{e.message}"
      {}
    end

    # Walk up from the working directory so the file works from subdirectories,
    # then fall back to the user's home.
    def find_config_file
      dir = Dir.pwd
      loop do
        candidate = File.join(dir, CONFIG_FILENAME)
        return candidate if File.exist?(candidate)

        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
      home = File.join(Dir.home, CONFIG_FILENAME)
      File.exist?(home) ? home : nil
    end

    def normalize!
      @bot_logins = Array(@bot_logins).map { |b| b.to_s.downcase }.uniq
      @teams = {} if @teams.nil?
      @cache_db_path = File.expand_path(@cache_db_path.to_s)
      @days = @days.to_i
    end
  end
end
