class UsersController < ApplicationController

  before_filter :authenticate_user!

  def edit
    @user = User.find_by_token(params[:id]) || User.find_by_id(params[:id]) || current_user
    2.times { @user.pauses.build }
  end

  def update
    @user = User.find_by_token(params[:id]) || User.find(params[:id])

    if @user.update_attributes(user_params)
      flash[:notice] = "Updated Account Info"
    else
      flash[:alert] = @user.errors.full_messages.to_sentence
    end

    redirect_to edit_user_path(@user)
  end

  def my_ratings
    rating_calculator = Housekeeper::RatingCalculator.new(current_user)
    @overall_rating = rating_calculator.last_30_day_overall_rating
    @service_rating = rating_calculator.last_30_day_service_rating
    @reliability_rating = rating_calculator.last_30_day_reliability_rating
    render "/users/housekeepers/my_ratings"
  end

  def download_app
    render "/users/housekeepers/download_app", layout: false
  end

  def pay_statements
    render "/users/housekeepers/pay_statements"
  end

  def tos_summary
    @tos_agreement = TosAgreement.last
  end

  def tos_details
    tos_agreement = TosAgreement.last
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true)
    @tos = markdown.render(tos_agreement.content)
  end

  def accept_tos
    tos_agreement = TosAgreement.find(params[:tos_agreement_id])
    TosAcceptance.create(
      user_id: current_user.id,
      tos_agreement_id: tos_agreement.id,
      tos_agreement_content: tos_agreement.content,
      accepted_at: Time.current,
      accepted_from_ip: current_user.current_sign_in_ip
    )
    redirect_to params[:redirect_to]
  end

  def disabled
    render layout:false
  end

  protected

  def user_params
    params.require(:user).permit(
        :first_name, :last_name, :phone, :general_notes, :referred_by_user_id,
        preference_attributes: [
            :id,
            :mon_service, :tue_service, :wed_service, :thu_service, :fri_service, :sat_service, :sun_service,
            :mon_start, :mon_end, :tue_start, :tue_end, :wed_start, :wed_end, :thu_start, :thu_end,
            :fri_start, :fri_end, :sat_start, :sat_end, :sun_start, :sun_end
        ],
        pauses_attributes: [:id, :start_at, :end_at, :_destroy]
    )
  end

  def address_params
    params.require(:address).permit(:address, :suite, :notes)
  end

end
