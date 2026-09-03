# frozen_string_literal: true

module ReviewLens
  module Calculators
    # The reviewer path needs exactly one statistic.
    module Median
      module_function

      # @param values [Array<Numeric>]
      # @return [Numeric, nil] nil for an empty set
      def call(values)
        sorted = Array(values).compact.sort
        return nil if sorted.empty?

        mid = sorted.length / 2
        return sorted[mid] if sorted.length.odd?

        (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end
  end
end
