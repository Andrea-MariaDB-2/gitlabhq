# frozen_string_literal: true

class JiraConnect::EventsController < JiraConnect::ApplicationController
  # See https://developer.atlassian.com/cloud/jira/software/app-descriptor/#lifecycle

  skip_before_action :verify_atlassian_jwt!
  before_action :verify_asymmetric_atlassian_jwt!

  def installed
    unless Feature.enabled?(:jira_connect_installation_update, default_enabled: :yaml)
      return head :ok if current_jira_installation
    end

    success = current_jira_installation ? update_installation : create_installation

    if success
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def uninstalled
    if JiraConnectInstallations::DestroyService.execute(current_jira_installation, jira_connect_base_path, jira_connect_events_uninstalled_path)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  private

  def create_installation
    JiraConnectInstallation.new(create_params).save
  end

  def update_installation
    current_jira_installation.update(update_params)
  end

  def create_params
    transformed_params.permit(:client_key, :shared_secret, :base_url)
  end

  def update_params
    transformed_params.permit(:shared_secret, :base_url)
  end

  def transformed_params
    @transformed_params ||= params.transform_keys(&:underscore)
  end

  def verify_asymmetric_atlassian_jwt!
    asymmetric_jwt = Atlassian::JiraConnect::AsymmetricJwt.new(auth_token, jwt_verification_claims)

    return head :unauthorized unless asymmetric_jwt.valid?

    @current_jira_installation = JiraConnectInstallation.find_by_client_key(asymmetric_jwt.iss_claim)
  end

  def jwt_verification_claims
    {
      aud: jira_connect_base_url(protocol: 'https'),
      iss: transformed_params[:client_key],
      qsh: Atlassian::Jwt.create_query_string_hash(request.url, request.method, jira_connect_base_url)
    }
  end
end
