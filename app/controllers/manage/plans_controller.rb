module Manage
  class PlansController < BaseController

    before_action :set_plan, only: [:edit, :update, :destroy]
    respond_to :html

    def index
      @status = filter_by_status
      @city   = filter_by_city
      @plans  = Plan.all
      @plans  = @plans.where(city: @city)     if @city.present?
      @plans  = @plans.where(status: @status) if @status.present?
    end

    def new
      @plan = Plan.new
      @cities = City::CITIES
      @eligible_plan_groups = Plan::ELIGIBLE_GROUPS
    end

    def create
      @plan = Plan.new(plan_params)

      if @plan.save
        CustomPlans::StripePlan.new(@plan).create_stripe_plan!
        flash[:notice] = "Plan was successfully created."
        redirect_to manage_plans_path
      else
        flash[:notice] = "Error occurred. #{e.message}"
        redirect_to :back
      end
    rescue => e
      @plan.errors.add(:stripe_error, e.message)
    end

    def edit
      @plan
      @active_plans = Plan.active.where.not(id: @plan.id)
    end

    def update
      if @plan.update!(update_plan_params)
        flash[:notice] = "Plan was successfully updated."
      end

      redirect_to manage_plans_path
    end

    private

    def filter_by_status
      params[:search].try(:[], 'status')
    end

    def filter_by_city
      params[:search].try(:[], 'city')
    end

    def set_plan
      @plan = Plan.find(params[:id])
    end

    def plan_params
      params.require(:plan).permit(:name, :city, :price_in_cents, :stripe_plan_id, :weekly_quantity, :duration_per_appointment_in_minutes, :status, :mon_service, :tue_service, :wed_service, :thu_service, :fri_service, :sat_service, :sun_service, :eligible_groups => [])
    end

    def update_plan_params
      params.require(:plan).permit(:new_stripe_plan_id, :status)
    end

  end
end