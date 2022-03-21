# frozen_string_literal: true

module MergeRequests
  module Mergeability
    class CheckOpenStatusService < CheckBaseService
      def execute
        if merge_request.open?
          success
        else
          failure
        end
      end

      def skip?
        false
      end

      def cacheable?
        false
      end
    end
  end
end
