# frozen_string_literal: true

module ReviewLens
  module Presentation
    # Replaces real logins with stable stand-in names so a team report can be
    # shared more widely without exposing who is who.
    class Anonymizer
      # Neutral, memorable stand-ins. Distinct enough to follow one person
      # down a table without implying anything about them. Override via
      # Configuration#anonymous_names.
      DEFAULT_NAMES = %w[
        Albatross Avocet Bittern Bunting Chaffinch Cormorant
        Crossbill Curlew Dipper Dunlin Egret Fieldfare
        Firecrest Gadwall Gannet Godwit Goldcrest Goshawk
        Greenshank Harrier Hoopoe Jackdaw Kestrel Kingfisher
        Kittiwake Lapwing Linnet Merlin Nightjar Nuthatch
        Osprey Peregrine Petrel Pipit Plover Puffin
        Redshank Redstart Sanderling Shearwater Siskin Skylark
        Stonechat Swift Teal Turnstone Wagtail Whimbrel
        Wheatear Yellowhammer
      ].freeze

      def initialize(names: nil)
        @names = Array(names).reject { |n| n.to_s.empty? }
        @names = DEFAULT_NAMES if @names.empty?
        @mapping = {}
        @next_index = 0
      end

      # Get the anonymized name for a username (creates mapping if needed)
      def anonymize(username)
        return username if username.nil? || username.empty?

        @mapping[username] ||= assign_character
      end

      # Anonymize all usernames in a reviewers array
      def anonymize_reviewers(reviewers)
        reviewers.map do |reviewer|
          anonymize_reviewer(reviewer.dup)
        end
      end

      # Anonymize a single reviewer hash
      def anonymize_reviewer(reviewer)
        reviewer[:name] = anonymize(reviewer[:name]) if reviewer[:name]
        reviewer[:login] = anonymize(reviewer[:login]) if reviewer[:login]
        reviewer
      end

      # Anonymize watch list items (which may contain names in title/body/refs)
      def anonymize_watch_list(watch_list)
        watch_list.map do |item|
          anonymized = item.dup
          anonymized[:title] = anonymize_text(item[:title]) if item[:title]
          anonymized[:body] = anonymize_text(item[:body]) if item[:body]
          anonymized[:refs] = item[:refs]&.map { |ref| anonymize_text(ref) }
          anonymized
        end
      end

      # Anonymize usernames that appear in free text
      def anonymize_text(text)
        return text if text.nil?

        result = text.dup
        @mapping.each do |original, replacement|
          result = result.gsub(original, replacement)
        end
        result
      end

      # Get the current mapping (for debugging/testing)
      attr_reader :mapping

      private

      def assign_character
        character = @names[@next_index % @names.length]
        @next_index += 1
        character
      end
    end
  end
end
