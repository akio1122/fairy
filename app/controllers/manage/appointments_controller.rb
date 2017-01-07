module Manage
  class AppointmentsController < BaseController

    include UserNotification

    before_filter :set_appointment, only: [:edit, :show, :update, :restore]

    def new
      @customer = User.find_by id: params.require(:customer_id)
      @appointment = Appointment.new address_id: @customer.address.id, pass_id: @customer.latest_pass.id
    end

    def create
      @appointment = Appointment.new appointment_params
      if @appointment.save
        redirect_to :back, notice: 'Appointment created!'
      else
        redirect_to :back, alert: "Failed to create appointment! - #{@appointment.errors.full_messages.to_sentence}"
      end
    end

    def show
    end

    def edit
    end

    def update
      @appointment.assign_attributes(appointment_params)
      hk_changed = @appointment.housekeeper_id_changed?

      if @appointment.save
        if hk_changed && @appointment.requires_notifying_customer_of_change?
          send_notifications_for_changed_appointment(@appointment)
        end
        redirect_to :back, notice: 'Appointment updated!'
      else
        redirect_to :back, alert: "Failed to update appointment! - #{@appointment.errors.full_messages.to_sentence}"
      end
    end

    def restore
      @version = @appointment.versions.find params[:version_id]
      if @version.reify
        @version.reify.save!
        redirect_to :back, notice: 'Appointment reverted!'
      else
        @version.item.destroy
        redirect_to :back, notice: 'Appointment deleted!'
      end
    end

    def checklist_task_history_modal
      @checklist_task = ChecklistTask.with_deleted.find(params[:checklist_task_id])
    end

    private

    def set_appointment
      @appointment = Appointment.find_by(token: params[:id])
    end

    def appointment_params
      params.require(:appointment).permit(
          :address_id, :scheduled_at, :start_at, :end_at, :key_check_in, :key_check_out,
          :housekeeper_id, :focus, :skip, :pass_id, :consultation, :scheduled_duration_in_minutes,
          :hard_break, :within_time_window, :authorized_by_resident
      )
    end

  end
end