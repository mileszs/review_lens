# frozen_string_literal: true

# Stands in for Open3 in GitHubClient specs: records the commands it was asked
# to run and replays queued results, so nothing ever shells out to real `gh`.
class FakeExecutor
  Result = Struct.new(:out, :err, :ok)

  Status = Struct.new(:ok) do
    def success? = ok
  end

  def self.ok(body) = Result.new(body, '', true)
  def self.failure(err) = Result.new('', err, false)

  attr_reader :commands

  def initialize(results = [])
    @results = results
    @commands = []
  end

  def capture3(*cmd)
    @commands << cmd
    result = @results.shift || self.class.ok('[]')
    [result.out, result.err, Status.new(result.ok)]
  end
end
