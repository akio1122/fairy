class FairyRegistrationsController < Devise::RegistrationsController
  before_filter :configure_permitted_parameters, :only => [:create]

  def create
    super
    Email.new.send_welcome(@user) if @user.persisted?
  end

  def check_availability
    params[:user][:password] = Devise.friendly_token[0,20]
    build_resource(sign_up_params)

    if resource.save
      # send mail here to set password
      render "/pages/confirmation", layout: "pages"
    else
      render json: {errors: resource.errors}, status: :unprocessable_entity
    end
  end

  protected

    def configure_permitted_parameters
      devise_parameter_sanitizer.for(:sign_up) << :role
      devise_parameter_sanitizer.for(:sign_up) << :first_name
      devise_parameter_sanitizer.for(:sign_up) << :last_name
      devise_parameter_sanitizer.for(:sign_up) << :phone
    end

end
