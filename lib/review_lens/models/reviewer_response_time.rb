# frozen_string_literal: true

require 'time'

module ReviewLens
  module Models
    # Value object representing a reviewer's response time to a review request
    class ReviewerResponseTime
      attr_reader :reviewer_login, :pr_number, :requested_at, :first_review_at, :response_hours

      def initialize(reviewer_login:, pr_number:, requested_at:, first_review_at:,
                     response_hours: nil, business_hours: Calculators::BusinessHours.new)
        @reviewer_login = reviewer_login
        @pr_number = pr_number
        @requested_at = requested_at
        @first_review_at = first_review_at
        @business_hours = business_hours
        @response_hours = response_hours || calculate_response_hours
      end

      def responded?
        !@first_review_at.nil?
      end

      private

      def calculate_response_hours
        return nil unless @requested_at && @first_review_at

        requested = @requested_at.is_a?(Time) ? @requested_at : Time.parse(@requested_at)
        reviewed = @first_review_at.is_a?(Time) ? @first_review_at : Time.parse(@first_review_at)

        @business_hours.between(requested, reviewed)
      end
    end
  end
end
