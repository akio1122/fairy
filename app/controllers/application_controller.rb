class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :rails_admin_record_path, :rails_admin_record_path, :rails_admin_new_record_path, :rails_admin_edit_record_path
  before_filter :set_paper_trail_whodunnit
  before_action :store_current_location, unless: :devise_controller?
  before_action :check_disabled

  helper_method :mailbox, :conversation

  def after_sign_in_path_for(resource)
    if resource.is_a?(User) && resource.is_concierge?
      concierge_buildings_path
    elsif resource.is_a?(User) &&
          ( resource.groups.include?("housekeeper-android-app") ||
            resource.groups.include?("housekeeper-ios-app")
          )
      download_app_path
    else
      stored_location = stored_location_for(:user)
      stored_location = appointments_path if stored_location.blank? || stored_location == "/"
      stored_location
    end
  end

  def user_admin_path(user)
    request.base_url + rails_admin.show_path(model_name: 'user', id: user.id)
  end

  def pass_admin_path(pass)
    request.base_url + rails_admin.show_path(model_name: 'pass', id: pass.id)
  end

  def appointment_admin_path(appointment)
    request.base_url + rails_admin.show_path(model_name: 'appointment', id: appointment.id)
  end

  def rails_admin_record_path(record)
    rails_admin.show_path(model_name: record.class.name.downcase, id: record.id)
  end

  def rails_admin_new_record_path(klass)
    rails_admin.new_path(model_name: klass)
  end

  def rails_admin_edit_record_path(record)
    rails_admin.edit_path(model_name: record.class.name.downcase, id: record.id)
  end

  def auto_login(user=nil)
    if params[:auth_token].present?
      user = User.find_by_authentication_token(params[:auth_token])
    end

    if user.present?
      sign_out(current_user) if current_user.present?
      sign_in(user)
      PaperTrail.whodunnit = user.name
    end
  end

  def parse_text_into_date(date_text)
    # %Y-%m-%d %H:%M:%S
    zone = "Pacific Time (US & Canada)"
    ActiveSupport::TimeZone[zone].parse(date_text)
  end

  private

  def mailbox
    @mailbox ||= current_user.mailbox
  end

  def conversation
    @conversation ||= mailbox.conversations.find(params[:id])
  end

  protected

  def parse_date
    @date = parse_text_into_date(params[:date] || Time.current.to_date.to_s).to_date
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_up) << :referred_by_user_id << :role << {address_attributes: [:full_address]}
    devise_parameter_sanitizer.for(:account_update) { |u| u.permit(:password, :password_confirmation, :current_password) }
  end

  # Overwriting the sign_out redirect path method
  def after_sign_out_path_for(resource_or_scope)
    Rails.env.development? ? root_path : FrontEndApp::ROOT_URL
  end

  def location_track_params
    params.permit(:longitude, :latitude, :accuracy, :location_error)
  end

  def store_current_location
    store_location_for(:user, request.url)
  end

  def check_disabled
    if user_signed_in? && current_user.is_disabled?
      if current_user.is_housekeeper?
        if !on_a_disabled_hk_allowed_path?
          redirect_to pay_statements_path
        end
      else
        sign_out(current_user)
        redirect_to new_user_session_path, notice: "Your account is marked as disabled. Please contact support@itsfairy.com if this is an error." and return
      end
    end
  end

  def disabled_hk_allowed_paths
    [
      {controller: "users", action: "pay_statements"},
      {controller: "admin", action: "become"}
    ]
  end

  def on_a_disabled_hk_allowed_path?
    disabled_hk_allowed_paths.include?({controller: params[:controller], action: params[:action]})
  end

  def authorize_admin!
    redirect_to root_path, alert: 'You are not authorized to access this page!' if !current_user.is_admin?
  end

end
