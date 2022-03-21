# frozen_string_literal: true

module Ci
  module Runners
    class AssignRunnerService
      # @param [Ci::Runner] runner: the runner to assign to a project
      # @param [Project] project: the new project to assign the runner to
      # @param [User] user: the user performing the operation
      def initialize(runner, project, user)
        @runner = runner
        @project = project
        @user = user
      end

      def execute
        return false unless @user.present? && @user.can?(:assign_runner, @runner)

        @runner.assign_to(@project, @user)
      end

      private

      attr_reader :runner, :project, :user
    end
  end
end

Ci::Runners::AssignRunnerService.prepend_mod
