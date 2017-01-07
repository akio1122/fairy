class Api::ApisController < ApplicationController

  skip_before_action :verify_authenticity_token

  acts_as_token_authentication_handler_for User, fallback_to_devise: false

  respond_to :json

  before_action :set_global_request
  after_action :remove_global_request

  def api_user
    User.find_by_authentication_token(request.headers["token"])
  end

  def token_authenticated?
    render status: :unauthorized, text: "Token: Access denied." if api_user.nil?
  end

  def http_basic_authenticated?
    authenticate_or_request_with_http_basic do |username, password|
      username == ENV["API_AUTH_USERNAME"] && password == ENV["API_AUTH_PASSWORD"]
    end
  end

  def current_user
    api_user
  end

  def admin_only
    render status: :unauthorized, text: "Admin only" if !api_user.is_admin?
  end

  def remove_null_values(hash)
    hash.map do |apt| # Removing nil values and the dropped_by association
      apt.delete_if do |k, v|
        # for nested hashes
        if v.is_a?(Hash)
          v.delete_if do |k2, v2|
            v2.blank?
          end
        end
        # For some reason the dropped_by association keeps showing up
        v.blank? || k == "dropped_by"
      end
    end
  end

  private

  def set_global_request
    $request = request
  end

  def remove_global_request
    $request = nil
  end

end