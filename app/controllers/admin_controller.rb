class AdminController < ApplicationController

  before_filter :authenticate_user!, except: [:become]
  before_filter :check_admin, except: [:become]

  def become
    user = User.find_by email: params[:email]
    redirect_url = nil
    if user
      if user.is_admin?
        redirect_url = session[:admin_prev_path]
        session[:admin_email] = nil
        session[:admin_prev_path] = nil
      elsif user.is_housekeeper?
        session[:admin_email] = current_user.email
        session[:admin_prev_path] = request.referer
      end
      sign_in user, bypass: true
    else
      flash[:error] = "Please provide the email of the user you wish to become"
    end
    redirect_to (redirect_url || appointments_path)
  end

  def watcher
    @housekeepers = User.housekeepers.active
  end

  def daily_report
    connection = ActiveRecord::Base.connection
    repository = Reports::SummaryResultsRepository.new(connection)
    calculator = Reports::SummaryReportCalculator.new(repository, Time.zone.name)

    if params[:date]
      zone = "Pacific Time (US & Canada)"
      @date = ActiveSupport::TimeZone[zone].parse(params[:date]).to_date
    else
      @date = Time.current.to_date
    end

    report = calculator.daily(@date)
    @report_in_html = Reports::SummaryTablePresenter.new(report.summary).to_html
  end

  def schedule
    @housekeepers = User.housekeepers.active.without_brand_ambassadors.order("first_name ASC")
    if params[:housekeeper_id] && params[:housekeeper_id] == "all"
      @housekeepers_to_display = @housekeepers
    elsif params[:housekeeper_id]
      @hk = User.find(params[:housekeeper_id])
      @housekeepers_to_display = [@hk]
    else
      @hk = @housekeepers.first
      @housekeepers_to_display = [@hk]
    end
    @date = params[:date] ? Date.parse(params[:date]) : Time.current.to_date
    @start_of_week = @date.beginning_of_week
  end

  def hk_utilization
    @hks = User.housekeepers.active.without_brand_ambassadors.order(:first_name).includes(:preference)
    @hks_by_city = {}
    @hks.map do |hk|
      @hks_by_city[hk.city] ||= []
      @hks_by_city[hk.city] << hk
    end
    @date = params[:date] ? Date.parse(params[:date]) : Time.current.to_date
    @start_of_week = @date.beginning_of_week

    respond_to do |format|
      format.html
      format.xlsx do
        filename = "HK Utilization #{@start_of_week} ~ #{@date.end_of_week}.xlsx"
        response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
      end
    end
  end

  def hk_paystubs_list
    @hks = User.housekeepers.order("first_name asc")
  end

  def hk_paystubs
    @hk = User.find_by_id(params[:housekeeper_id])
  end

  def view_appointment_as_housekeeper
    @appointment = Appointment.find params[:id]
    @customer = @appointment.address.try(:user)
  end

  def breakage
    @city = City.parameterized_cities.keys.include?(params[:city]) ? City.parameterized_cities[params[:city]] : City::SAN_FRANCISCO
    @date = params[:date] ? Date.parse(params[:date]) : Time.current.to_date
    @users_requiring_service = User.requiring_service_on(@date)
    @appointments = Appointment.appointments_on(@date).in_city(@city).not_consultation.without_skips.includes(address: {user: [:primary_matches]})
    @authorized_exclusive_appointments = @appointments.hard_breaks.authorized_by_resident.order(housekeeper_id: :asc, scheduled_at: :asc).select { |apt| apt.exclusive_match? }
    @authorized_not_exclusive_appointments = @appointments.hard_breaks.authorized_by_resident.order(housekeeper_id: :asc, scheduled_at: :asc).select { |apt| !apt.exclusive_match? }
    @non_authorized_exclusive_appointments = @appointments.hard_breaks.not_yet_authorized_by_resident.order(housekeeper_id: :asc, scheduled_at: :asc).select { |apt| apt.exclusive_match? }
    @non_authorized_not_exclusive_appointments = @appointments.hard_breaks.not_yet_authorized_by_resident.order(housekeeper_id: :asc, scheduled_at: :asc).select { |apt| !apt.exclusive_match? }
  end

  def remove_hard_breaks_not_requiring_service
    date = Date.parse(params[:date])
    Jarvis::Breakage.remove_appointments_not_supposed_to_be_scheduled(date)
    redirect_to breakage_path(date: date.strftime("%Y-%m-%d"))
  end

  private

  def check_admin
    redirect_to root_path unless current_user && current_user.is_admin?
  end

end
