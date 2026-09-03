# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module ReviewLens
  # Command line entry point: `fetch`, `report`, `run`.
  #
  # Kept deliberately thin -- it parses options, wires objects together, and
  # prints. All behaviour lives in the classes it calls.
  class CLI
    COMMANDS = %w[fetch report run version help].freeze

    def self.start(argv, stdout: $stdout, stderr: $stderr)
      new(stdout: stdout, stderr: stderr).run(argv)
    end

    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    # @return [Integer] process exit status
    def run(argv)
      command, options = parse(argv)
      case command
      when 'version' then @stdout.puts(ReviewLens::VERSION)
      when 'help' then @stdout.puts(banner)
      when 'fetch' then fetch(config(options))
      when 'report' then report(config(options), options)
      when 'run' then run_both(config(options), options)
      end
      0
    rescue Error => e
      @stderr.puts("review-lens: #{e.message}")
      1
    rescue Interrupt
      @stderr.puts("\nreview-lens: interrupted")
      130
    end

    private

    def parse(argv)
      args = argv.dup
      command = COMMANDS.include?(args.first) ? args.shift : 'help'
      options = {}
      parser(options).parse!(args)
      [command, options]
    end

    def parser(options)
      OptionParser.new do |o|
        o.banner = banner
        target_options(o, options)
        window_options(o, options)
        output_options(o, options)
        o.on('-h', '--help', 'Show this message') { options[:help] = true }
      end
    end

    def target_options(opts, options)
      opts.on('--repo OWNER/NAME', 'Repository to analyze') { |v| options[:repo] = v }
      opts.on('--base BRANCH', 'Base branch (default main)') { |v| options[:base_branch] = v }
      opts.on('--db PATH', 'SQLite path') { |v| options[:cache_db_path] = v }
      opts.on('--config PATH', 'Config file path') { |v| options[:config_path] = v }
    end

    def window_options(opts, options)
      opts.on('--days N', Integer, 'Rolling window in days (default 90)') { |v| options[:days] = v }
      opts.on('--since DATE', 'Window start (YYYY-MM-DD)') { |v| options[:since] = v }
      opts.on('--until DATE', 'Window end (YYYY-MM-DD)') { |v| options[:until] = v }
      opts.on('--fresh', 'Re-fetch everything, ignoring stored PRs') { options[:fresh] = true }
    end

    def output_options(opts, options)
      opts.on('--login LOGIN', "Only build this person's report") { |v| options[:login] = v }
      opts.on('--only a,b', Array, 'Only build these logins') { |v| options[:only] = v }
      opts.on('--out DIR', 'Output directory (default review-lens/)') { |v| options[:output_dir] = v }
      opts.on('--[no-]team', 'Build the team dashboard (default yes)') { |v| options[:team] = v }
      opts.on('--[no-]individual', 'Build per-person reports (default yes)') { |v| options[:individual] = v }
      opts.on('--anonymize', 'Also write an anonymized team report') { options[:anonymize] = true }
      opts.on('--show-flags', 'Include evaluative labels in the team report') { options[:show_flags] = true }
    end

    def banner
      <<~TEXT
        review-lens #{ReviewLens::VERSION} -- humane code review metrics

        Usage:
          review-lens fetch  --repo owner/name [--days 90]   Pull PR data into the local store
          review-lens report --repo owner/name [--days 90]   Build reports from stored data
          review-lens run    --repo owner/name [--days 90]   Fetch, then report

        Individual reports name only their subject; peers appear as unlabeled
        points. They are written locally and are not meant to be published.

        Options:
      TEXT
    end

    def config(options)
      passthrough = options.slice(
        :repo, :days, :base_branch, :cache_db_path, :output_dir, :fresh, :show_flags, :config_path
      )
      cfg = Configuration.new(**passthrough)
      raise ConfigurationError, 'a repository is required: --repo owner/name' if cfg.repo.to_s.empty?

      cfg
    end

    def window(cfg, options)
      return DateRange.between(since: options[:since], until_time: options[:until], timezone: cfg.timezone) if
        options[:since]

      DateRange.rolling(days: options[:days] || cfg.days, timezone: cfg.timezone)
    end

    def with_store(cfg)
      store = Cache::Store.new(db_path: cfg.cache_db_path)
      yield store, Cache::GithubCache.new(cache_store: store)
    ensure
      store&.close
    end

    def fetch(cfg, options = {})
      since, until_time = window(cfg, options)
      with_store(cfg) do |_store, cache|
        @stdout.puts("Fetching #{cfg.repo} (#{since.strftime('%Y-%m-%d')} to #{until_time.strftime('%Y-%m-%d')})...")
        result = Ingest.new(config: cfg, cache: cache).call(since: since, until_time: until_time) do |p|
          @stdout.print("\r  #{p.done}/#{p.total} pull requests")
          @stdout.flush
        end
        @stdout.puts(
          "\r  #{result[:total]} pull requests " \
          "(#{result[:fetched]} new, #{result[:skipped]} already stored)"
        )
      end
    end

    def report(cfg, options)
      since, until_time = window(cfg, options)
      with_store(cfg) do |store, cache|
        raise NoDataError, 'No data stored yet. Run: review-lens fetch' if store.empty?

        metrics = Analyzer.new(config: cfg, cache: cache).call(since: since, until_time: until_time)
        write_reports(cfg, options, metrics, since, until_time)
      end
    end

    def run_both(cfg, options)
      fetch(cfg, options)
      report(cfg, options)
    end

    def write_reports(cfg, options, metrics, since, until_time)
      dir = File.expand_path(cfg.output_dir)
      FileUtils.mkdir_p(dir)
      shared = { metrics: metrics, week_start: since, week_end: until_time, config: cfg }

      write_team(dir, shared, options) unless options[:team] == false
      write_individual(cfg, dir, shared, options, metrics) unless options[:individual] == false
      @stdout.puts("\nReports written to #{dir}")
    end

    def write_team(dir, shared, options)
      path = File.join(dir, 'team.html')
      Presentation::TeamReport.new(**shared).write(path)
      @stdout.puts("  team dashboard      #{path}")
      return unless options[:anonymize]

      anon = File.join(dir, 'team-anonymized.html')
      Presentation::TeamReport.new(**shared, anonymize: true).write(anon)
      @stdout.puts("  anonymized          #{anon}")
    end

    def write_individual(cfg, dir, shared, options, metrics)
      people = target_logins(cfg, shared, options)
      return @stdout.puts('  (no reviewers matched)') if people.empty?

      out = File.join(dir, 'reviewers')
      FileUtils.mkdir_p(out)
      guard_output_dir(out)
      people.each do |login|
        Presentation::IndividualReport.new(**shared, focus_login: login).write(File.join(out, "#{login}.html"))
      end
      @stdout.puts("  #{people.length} private report(s)  #{out}/")
      @stdout.puts('  These are private. Share each person only their own.')
      metrics
    end

    def target_logins(_cfg, shared, options)
      return [options[:login]] if options[:login]

      mapper = Presentation::DataMapper.new(**shared)
      humans = mapper.reviewers.reject { |r| r[:bot] }.map { |r| r[:name] }
      options[:only] ? humans & options[:only].map(&:strip) : humans
    end

    # These files describe named individuals; keep them out of git by default.
    def guard_output_dir(dir)
      ignore = File.join(dir, '.gitignore')
      File.write(ignore, "*\n") unless File.exist?(ignore)
    end
  end
end
