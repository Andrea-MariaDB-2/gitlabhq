# frozen_string_literal: true
module MergeRequests
  module Mergeability
    class CheckBrokenStatusService < CheckBaseService
      def execute
        if merge_request.broken?
          failure
        else
          success
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
