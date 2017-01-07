class Api::V1::AppointmentsController < Api::ApisController
  include HousekeeperNotification
  include AppointmentsDoc

  authorize_by_token = [
    :first_session,
    :all,
    :cancel,
    :cannot_schedule,
    :create_trial,
    :cancel_trial_appointment,
    :first_session_email,
    :bulk_update,
    :authorize,
    :leave_feedback
  ]
  before_filter :token_authenticated?, :only => authorize_by_token
  before_filter :http_basic_authenticated?, :except => authorize_by_token
  before_filter :admin_only, :only => [:bulk_update]

  def available_days
    days = []
    today = Time.current.to_date
    # Default to an SF building if no building params provided
    building = params[:building_id].present? ? Building.find(params[:building_id]) : Building.first
    brand_ambassador_ids = building.neighborhood.housekeepers.does_consultations.pluck(:id)

    ConsultationSlot.where(housekeeper_id: brand_ambassador_ids).by_day.each do |date, slots|
      days << {
        alternate_name: date == today + 1.day ? "Tomorrow" : nil,
        day_of_week:    date.strftime('%A'),
        date:           date.strftime("%B %-d, %Y"),
        available:      true,
        hours:          slot_hours(slots, building)
      }
    end
    render json: {
      days: days
    }
  end

  def first_session
    user = api_user
    user = assign_user_first_session(user)

    ChecklistTemplateTask.create_default_set_for(user)

    NotificationPreference.create_default_for(user)

    if user.save
      user.set_default_service_preference_based_on_plan
      user.create_referral_promo_code(false) unless user.referral_code.present?

      building = user.address.assign_to_building(user.city)

      user.assign_to_city if user.city.nil?

      create_stripe_customer_result = user.create_stripe_customer(params[:card_token]) if params[:card_token].present?

      if create_stripe_customer_result.present? && create_stripe_customer_result[:status] == :success
        user.update_attributes(status: User::CREDIT_CARD_ENTERED)
        render json: {
          user: user.as_json(include: [:address, :appointments, :credit_cards])
        }
      else
        render json: {
          user: user.as_json(include: [:address, :appointments]),
          errors: create_stripe_customer_result.present? ? create_stripe_customer_result[:message] : nil
        }
      end
    else
      render json: {
        errors: user.errors.full_messages
      }
    end
  rescue => error
    render json: {
      errors: error.message
    }
  end

  def first_session_email
    Email.new.confirmation_of_first_session(api_user)
    render json: {
      message: "First session email to #{api_user.name} successfully sent."
    }
  end

  def all
    if params[:start_date].present? && params[:end_date].present?
      start_date = parse_text_into_date(params[:start_date]).beginning_of_day
      end_date = parse_text_into_date(params[:end_date]).end_of_day
      apts = api_user.appointments.where(scheduled_at: start_date..end_date)
    else
      apts = api_user.appointments
    end
    cleaned_apts = apts.as_json(
      :methods => [:time_window_times],
      :include => {
        :housekeeper => {
          :methods => [:detailed_profile]
        }
      }
    )

    render json: {
      appointments: remove_null_values(cleaned_apts)
    }
  end

  def leave_feedback
    appointment = api_user.appointments.find_by id: params[:id]
    @appointment = Customer::LeaveFeedback.new(appointment, feedback_params).run!

    if @appointment.errors.any?
      render json: {
        errors: @appointment.errors.full_messages.to_sentence
      }, status: :unprocessable_entity
    else
      render json: {
        message: "Appointment with ID:#{params[:id]} successfully updated."
      }
    end
  end

  def update
    appointment = api_user.appointments.find_by_id(params[:id])
    if appointment.present?
      if appointment.update(appointment_params)
        render json: {
          message: "Appointment with ID:#{params[:id]} successfully updated."
        }
      else
        render json: {
          errors: appointment.errors.full_messages.to_sentence
        }
      end
    else
      render json: {
        errors: "No appointment with ID:#{params[:id]} associated with this user."
      }
    end
  end

  def show
    appointment = api_user.appointments.find_by_id(params[:id])
    render json: {
      appointment: appointment.as_json(methods: [:time_window])
    }
  end

  def cancel
    appointment = api_user.appointments.find_by_id(params[:id])
    if appointment.present?
      mark_associated_consultation_slots_as_available(appointment, api_user)
      appointment.destroy
      api_user.latest_pass.destroy if api_user.latest_pass
      render json: {
        message: "Appointment with ID:#{params[:id]} successfully cancelled."
      }
    else
      render json: {
        message: "No appointment with ID:#{params[:id]} associated with this user."
      }
    end
  end

  def rating_categories
    render json: {
      categories: [
        "Notes not followed",
        "Unclear of items cleaned",
        "Low quality",
        "Bad timing",
        "Other"
      ]
    }
  end

  def cannot_schedule
    SlackPost.user_cannot_self_schedule_consultation_or_trial(api_user)
    ac = ActivityCategory.find_by_name(ActivityCategory::CANNOT_SCHEDULE_CONSULTATION_OR_TRIAL)
    Activity.create(
      user: api_user,
      activity_category: ac,
      occurred_at: Time.current,
      note: params[:note]
    )
    render json: {
      message: "Cannot schedule successfully logged."
    }
  end

  def create_trial
    appointment = create_trial_appointment
    SlackPost.user_self_signed_up_for_trial_appointment(api_user, appointment)
    render json: {
      appointment: appointment
    }
  rescue => error
    render json: {
      errors: error.message
    }
  end

  def cancel_trial_appointment
    appointment = Appointment.find(params[:appointment_id])
    if appointment.address.user == api_user
      SlackPost.user_self_cancels_trial_appointment(api_user, appointment)
      appointment.destroy
      render json: {
        message: "Appointment with ID:#{params[:appointment_id]} successfully cancelled."
      }
    else
      render json: {
        message: "User does not match the user on the appointment with ID:#{params[:appointment_id]}"
      }
    end
  rescue => error
    render json: {
      errors: error.message
    }
  end

  def bulk_update
    appointment_ids = params[:appointment_ids].split(",")
    appointments = Appointment.where(id: appointment_ids)
    appointments.each do |apt|
      apt.assign_attributes(appointment_params)
      apt.save!
    end
    render json: {
      message: "#{appointments.count} #{'appointment'.pluralize(appointments.count)} successfully updated."
    }
  rescue => error
    render json: {
      errors: error.message
    }
  end

  def authorize
    apt = Appointment.find_by_id(params[:id])
    if apt.nil?
      render json: {
        message: "Appointment with ID: #{params[:id]} not found"
      }
    end

    if api_user != apt.customer
      render json: {
        message: "Permission denied"
      }
    else
      apt.authorized_by_resident = true
      apt.save
      render json: {
        appointment: apt
      }
    end
  end

  def decline
    apt = Appointment.find_by_id(params[:id])
    if apt.nil?
      render json: {
        message: "Appointment with ID: #{params[:id]} not found"
      }
    end

    if api_user != apt.customer
      render json: {
        message: "Permission denied"
      }
    else
      apt.authorized_by_resident = false
      apt.save
      message = revoked_authorization_message(apt)
      Sms.new.run(apt.housekeeper, message)
      render json: {
        appointment: apt
      }
    end
  end

  protected

  def is_weekend(date)
    date.wday == 0 || date.wday == 6
  end

  def slot_hours(slots, building)
    hours = []
    slots.each do |slot|
      hours << {
        start_hour: (slot.start_at + City.hours_ahead_of_pst(building).hours).strftime('%l:%M %p').strip,
        end_hour:   (slot.end_at + City.hours_ahead_of_pst(building).hours).strftime('%l:%M %p').strip,
        available:  true
      }
    end
    hours
  end

  def assign_user_first_session(user)
    user.first_name = params[:first_name]
    user.last_name = params[:last_name]
    user.phone = params[:phone]
    user.password = params[:password]
    user.encrypted_password
    user.address.bedrooms = params[:bedrooms]
    user.plan = Plan.find_by_stripe_plan_id(params[:plan_id]) if params[:plan_id].present?
    user.status = User::SIGN_UP_COMPLETE
    user
  end

  def assign_appointment_first_session(appointment, user)
    appointment.address = user.address
    appointment.consultation = true
    appointment.scheduled_at = parse_text_into_date(params[:scheduled_at])
    appointment
  end

  def block_off_adjacent_consultation_slots(consultation_slot)
    before_appointment = appointment_before(consultation_slot, true)
    before_appointment.update_attributes(available: false) if before_appointment
    after_appointment = appointment_after(consultation_slot, true)
    after_appointment.update_attributes(available: false) if after_appointment
  end

  def mark_associated_consultation_slots_as_available(appointment, user)
    building = user.address.building
    brand_ambassador_ids = building.neighborhood.housekeepers.does_consultations.pluck(:id)
    consultation_slot = ConsultationSlot.where(start_at: appointment.scheduled_at - City.hours_ahead_of_pst(appointment.address.user).hours).where("housekeeper_id in (?)", brand_ambassador_ids).first
    if consultation_slot
      consultation_slot.update_attributes(available: true)
      # before_appointment = appointment_before(consultation_slot, false)
      # before_appointment.update_attributes(available: true) if before_appointment
      # after_appointment = appointment_after(consultation_slot, false)
      # after_appointment.update_attributes(available: true) if after_appointment
    end
  end

  def appointment_before(consultation_slot, available)
    if available
      ConsultationSlot.available.where(housekeeper_id: consultation_slot.housekeeper_id).where(start_at: consultation_slot.start_at - Calendar::MINUTES_PER_CONSULTATION.minutes).first
    else
      ConsultationSlot.unavailable.where(housekeeper_id: consultation_slot.housekeeper_id).where(start_at: consultation_slot.start_at - Calendar::MINUTES_PER_CONSULTATION.minutes).first
    end
  end

  def appointment_after(consultation_slot, available)
    if available
      ConsultationSlot.available.where(housekeeper_id: consultation_slot.housekeeper_id).where(start_at: consultation_slot.start_at + Calendar::MINUTES_PER_CONSULTATION.minutes).first
    else
      ConsultationSlot.unavailable.where(housekeeper_id: consultation_slot.housekeeper_id).where(start_at: consultation_slot.start_at + Calendar::MINUTES_PER_CONSULTATION.minutes).first
    end
  end

  def has_card_details
    params[:card_number].present? &&
    params[:card_exp_month].present? &&
    params[:card_exp_year].present? &&
    params[:card_cvc].present?
  end

  def feedback_params
    params.require(:appointment).permit(
      :feedback_sentiment,
      :feedback_for_housekeeper,
      :feedback_for_fairy,
      :rating_category_from_customer,
      :tip_in_cents
    )
  end

  def appointment_params
    params.require(:appointment).permit(
      :notes_from_customer,
      :rating_from_customer,
      :rating_comments_from_customer,
      :notes_from_housekeeper,
      :rating_from_housekeeper,
      :rating_comments_from_housekeeper,
      :focus,
      :skip,
      :housekeeper_id,
      :address_id,
      :customer_home,
      :scheduled_at,
      :start_at,
      :end_at,
      :key_check_in,
      :key_check_out,
      :hard_break,
      :deleted_at,
      :within_time_window
    )
  end

  def create_trial_appointment
    user = api_user
    address = user.address
    hk = User.find(params[:housekeeper_id])
    start_time = parse_text_into_date(params[:start_time]) # %Y-%m-%d %H:%M:%S
    duration = params[:duration]
    pass = user.latest_pass

    appointment = Appointment.create(
      address: address,
      housekeeper: hk,
      scheduled_at: start_time,
      scheduled_duration_in_minutes: duration,
      pass: pass
    )
    pass.update_attributes(end_at: appointment.scheduled_at.to_date) if appointment.scheduled_at > pass.end_at
    appointment
  end

end
