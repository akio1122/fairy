class Api::V1::HousekeepersApi::AppointmentsController < Api::V1::HousekeepersApi::BaseController
  before_action :housekeeper_restriction, except: [:show, :blocked_reasons, :override_checklist_reasons, :pickup]
  before_action :auto_login_to_web_app, only: :pickup

  def show
    render json: appointment, serializer: Housekeeper::AppointmentExtendedSerializer, anonymize_customer_data: params[:anonymize_customer_data]
  end

  def pickup
    redirect_to pickup_appointments_path
  end

  def pickup
    redirect_to pickup_appointments_path
  end

  def pickup
    redirect_to pickup_appointments_path
  end

  def pickup
    redirect_to pickup_appointments_path
  end

  def override_checklist_reasons
    render json: Appointment::OVERRIDE_CHECKLIST_REASONS
  end

  def override_checklist
    appointment.override_checklist = params[:override_checklist] || true
    appointment.override_checklist_reason = params.require(:override_checklist_reason) + params[:notes].to_s

    if appointment.save
      head :no_content
    else
      render json: { errors: appointment.errors }, status: :unprocessable_entity
    end
  end

  def update_tasks
    update_tasks_status(params)
    head :no_content
  end

  def resolve_task
    update_tasks_status({checklist_tasks: [{id: params[:task_id], completed: params[:completed].nil? ? true : !!params[:completed]}]})
    head :no_content
  end

  def resolve_special_request
    update_tasks_status({focus: {completed: params[:completed].nil? ? true : !!params[:completed]}})
    update_tasks
  end

  def check_in
    entry_type = params.require(:entry_type)
    if entry_type == 'key'
      start_appointment!(true)
    elsif entry_type == 'resident'
      start_appointment!
    else
      render json: { errors: [entry_type: ["is not valid, use one of (resident, key)"]] }, status: :unprocessable_entity
    end
  end

  def check_out
    appointment.end_at = Time.zone.parse(params[:end_at]) if params[:end_at].present?
    appointment.end_at ||= now
    update_tasks_status(params)

    if appointment.save
      Customer::FirstAppointmentCompleted.new(appointment.customer, appointment).run! if appointment.is_first_appointment?
      head :no_content
    else
      render json: { errors: appointment.errors }, status: :unprocessable_entity
    end
  end

  def blocked_reasons
    render json: valid_blocked_reasons
  end

  def blocked
    unless valid_blocked_reasons.include? params[:blocked_reason]
      return render json: { errors: [blocked_reason: "is not valid, allowed options: #{valid_blocked_reasons.join(", ")}"] }, status: :unprocessable_entity
    end

    appointment.blocked_at     = now
    appointment.blocked_reason = params[:blocked_reason]
    appointment.blocked_notes  = params[:blocked_notes]

    if appointment.save
      SlackPost.housekeeper_marked_blocked(appointment)
      head :no_content
    else
      render json: { errors: appointment.errors }, status: :unprocessable_entity
    end
  end

  def blocked_by_customer_request
    params[:blocked_reason] = Appointment::BLOCKED_BY_CUSTOMER_REQUEST
    blocked
  end

  def drop
    Housekeeper::Drop.new(current_user, nil, appointment, {
      drop_reason: params.require(:drop_reason),
      drop_message_to_customer: params[:drop_message_to_customer]
    }).run!

    head :no_content
  end

  def feedback_viewed
    appointment.feedback_for_housekeeper_viewed_at = now

    if appointment.save
      head :no_content
    else
      render json: { errors: appointment.errors }, status: :unprocessable_entity
    end
  end

  def reset
    # if appointment.scheduled_at < now - 30.minutes
    #   return render_error(:forbidden, 403, "You can't reset appointments schedulted more then half an hour ago")
    # end

    appointment.reset_state!
    head :no_content
  end

  def valid_drop_reasons
    render json: Appointment::VALID_DROP_REASONS
  end

  protected
  def valid_blocked_reasons
    Appointment::BLOCKED_REASONS
  end

  def update_tasks_status(data)
    checklist_tasks   = data[:checklist_tasks] || []
    completed_tasks   = checklist_tasks.select{|t| t[:completed] }.map{|t| t[:id]}
    incompleted_tasks = checklist_tasks.select{|t| !t[:completed]}.map{|t| t[:id]}
    scope             = appointment.checklist_tasks

    ActiveRecord::Base.transaction do
      scope.where(id: completed_tasks).update_all(updated_at: now, status: ChecklistTask::COMPLETED) if completed_tasks.any?
      scope.where(id: incompleted_tasks).update_all(updated_at: now, status: nil) if incompleted_tasks.any?
      if data[:focus].present? && appointment.focus.present?
        appointment.focus_resolved_at = data[:focus][:completed] ? now : nil
        appointment.save!
        appointment.reload
      end
    end
  end

  def start_appointment!(with_key=false)
    appointment.start_at = now
    appointment.key_check_in = now if with_key
    if appointment.save
      head :no_content
    else
      render json: { errors: appointment.errors }, status: :unprocessable_entity
    end
  end

  def appointment
    @appointment ||= Appointment.find(params[:appointment_id] || params[:id])
  end

  def housekeeper_restriction
    unless appointment.housekeeper_id == current_user.id
      render_error(:forbidden, 403, "Only Housekeeper<#{appointment.housekeeper_id}> can manage this appointment")
    end
  end

  def now
    Time.current
  end
end
