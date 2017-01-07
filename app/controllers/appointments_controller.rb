class AppointmentsController < ApplicationController
  PICK_UP_STRATEGY = :date_pick_up

  include UserNotification
  include HousekeeperNotification

  before_action :auto_login, :only => [:edit, :authorize, :decline]
  before_action :authenticate_user!
  before_action :check_tos_acceptance
  before_action :parse_date, only: [:index, :edit, :check_out_key, :check_in_key, :start_working, :end_working, :backup_confirm]
  before_action :check_prev_day_status, only: [:edit, :check_out_key, :check_in_key, :start_working]
  before_action :check_starting_status, only: [:edit, :check_out_key, :check_in_key, :end_working]

  def index
    @user = current_user
    if current_user.is_customer?
      @appointments = current_user.appointments.any? ? current_user.appointments.without_hard_breaks.reverse : []
      render "appointments/customer/index"
    elsif current_user.is_housekeeper?
      @availability = current_user.housekeeper_availabilities.on(@date).first
      @appointments = date_appointments
      @appointments_requiring_hk_conf = @appointments.requires_housekeeper_confirmation
                        .order(scheduled_at: :asc)
      @remaining_apts = current_user.remaining_apts(@date)
      @payment = Housekeeper::Payment.new(@date, [@user.id])
      @payment.run!
      @date_payment = @payment.daily_detail(@user.id, @date)
      @total_payment = @payment.build_daily_detail(@user.id, @date, @appointments.without_skips, [])
      @is_today = @date == Time.current.to_date
      set_furthest_drop_date
      render "appointments/housekeeper/index"
    end
  end

  def batch_create
    # check format of start_time
    is_start_time_valid = Time.strptime(params[:start_time], "%I:%M %P") rescue false
    if !is_start_time_valid
      flash[:error] = "Could not create appointment(s) because start time needs to be of format: '11:00 am'"
      redirect_to params[:redirect_to] and return
    end

    (params[:dates] || []).each do |d|
      appointment = Appointment.new(appointment_params)
      appointment.scheduled_at = "#{d} #{params[:start_time]}"
      appointment.consultation = true if appointment.address.no_appointments?
      appointment.save
    end
    redirect_to params[:redirect_to]
  end

  def edit
    @appointment = Appointment.find_by(token: params[:id])

    return redirect_to appointments_path unless owns_appointment(current_user, @appointment)

    if current_user.is_customer?
      render "appointments/customer/edit"
    elsif current_user.is_housekeeper?
      @customer = @appointment.address.user
      @availability = current_user.housekeeper_availabilities.on(@date)
      # @next_business_day = Calendar.business_days_in_the_future(@appointment.scheduled_at.to_date, 1) if @appointment.consultation
      render "appointments/housekeeper/edit"
    end
  end

  def update
    @appointment = Appointment.find_by(token: params[:id])
    @date = @appointment.scheduled_at.to_date
    redirect_to appointments_path(date: @date) and return if @appointment.scheduled_in_the_future?
    @appointment.update_attributes(appointment_params)

    if params[:appointment][:blocked_appointment].present?
      Housekeeper::Block.new(@appointment, params).run!

    elsif params[:appointment][:start_appointment].present?
      pending_apt = in_progress_apt
      if pending_apt.present?
        redirect_to appointments_path(date: @date), alert: end_appointment_message(pending_apt) and return
      end

      @appointment.start_at = Time.current
      @appointment.save
      @appointment.track(Location::START_APT, location_track_params)
      redirect_to edit_appointment_path(@appointment, date: @appointment.scheduled_at.to_date) and return

    elsif params[:appointment][:end_appointment].present?
      user = @appointment.address.user
      @appointment.end_at = Time.current
      @appointment.set_within_time_window
      previous_end_at = @appointment.end_at_was
      hk = @appointment.housekeeper

      @appointment.override_checklist = params[:appointment][:override_checklist]
      if @appointment.override_checklist
        @appointment.override_checklist_reason = params[:appointment][:override_checklist_reason]
      else
        @appointment.override_checklist_reason = nil
      end

      if @appointment.save
        @appointment.track(Location::END_APT, location_track_params)

        SlackPost.housekeeper_rating(@appointment) if @appointment.rating_from_housekeeper
        SlackPost.hk_not_lock_door(@appointment) if @appointment.reason_not_lock.present?

        # Only the first time the appointment was ended
        if previous_end_at.nil?
          Email.new.send_leave_rating(@appointment) unless @appointment.consultation
          Email.new.trial_ending_soon(user) if user.completed_second_last_trial?
          Email.new.trial_ended(user) if user.completed_last_trial?

          Customer::FirstAppointmentCompleted.new(user, @appointment).run! if @appointment.is_first_appointment?
        end
      else
        flash[:alert] = "Please call support to let them know of this error: #{@appointment.errors.full_messages.to_sentence}"
      end

    elsif params[:appointment][:customer_is_leaving_rating].present?
      if @appointment.is_rated_bad?
        Email.new.poor_rating_to_zendesk(@appointment, appointment_admin_path(@appointment))
        SlackPost.improvement_needed(@appointment.id)
      elsif @appointment.is_rated_good?
        SlackPost.delay.happiness_delivered(@appointment.id)
      end
    end

    redirect_to appointments_path(date: @appointment.scheduled_at.to_date)
  end

  def accept_notes
    respond_to do |format|
      @customer = User.find_by_token(params[:customer_id]) || User.find(params[:customer_id])
      @housekeeper = User.find_by_token(params[:housekeeper_id]) || User.find(params[:housekeeper_id])
      @appointment = Appointment.find_by(token: params[:appointment_id])

      latest_note = @customer.notes.ordered.last
      @housekeeper.accepted_notes << latest_note

      flash[:notice] = "Notes accepted! Please click \"Start Appointment\" to begin your appointment."

      format.json { render :json => { url: edit_appointment_path(@appointment) } }
    end
  end

  def destroy
    @appointment = Appointment.find_by(token: params[:id])
    if @appointment
      address = @appointment.address
      @appointment.destroy
      address.ordered_appointments.first.update_attributes(consultation: true) if address.appointments.any?
    else
      flash[:error] = "No appointment found with ID: #{params[:id]}. May have already been deleted."
    end
    redirect_to :back
  end

  def check_out_key
    pending_apt = in_progress_apt
    if pending_apt.present?
      redirect_to appointments_path(date: @date), alert: end_appointment_message(pending_apt) and return
    end
    @appointment = Appointment.find_by(token: params[:id])
    @appointment.key_check_out = Time.current
    @appointment.save
    redirect_to appointments_path(date: @date)
  end

  def check_in_key
    @appointment = Appointment.find_by(token: params[:id])
    @appointment.key_check_in = Time.current
    @appointment.save
    redirect_to appointments_path(date: @date)
  end

  def decline_availability
    hk = User.find(params[:hk_id])
    Housekeeper::Drop.new(hk, params[:date], nil, params).run!
    if hk.is_flex?
      hk.backup_slots.update_all(housekeeper_id: nil, claimed_at: nil, dropped_at: Time.current)
    end
    redirect_to params[:redirect_to]
  end

  def backup_confirm
    slot_id = params[:backup_confirm][:slot_id]
    @backup_slot = Housekeeper::BackupSlot.find(slot_id)
    @backup_slot.claim!(current_user)
    redirect_to appointments_path(date: @date)
  end

  def confirm_appointments
    ids = params[:appointment_ids_for_confirmation]
    if ids.present?
      apts = Appointment.where(id: ids)
      apts.each do |apt|
        apt.update_attributes(confirmed_by_housekeeper_at: Time.current)
        if apt.checklist_tasks.empty?
          Jarvis::Appointment.create_checklist_tasks(apt.customer, apt, apt.scheduled_at.to_date)
        end
        send_notifications_for_changed_appointment(apt) if apt.requires_notifying_customer_of_change?
      end
    end
    redirect_to params[:redirect_to]
  end

  def decline_appointments
    ha = HousekeeperAvailability.where(housekeeper_id: current_user.id, available_on: params[:date]).first_or_initialize
    ha.declined_more = true
    ha.save
    Jarvis::Controller.delay(retry: false).reassign_declined_appointments(
      params[:date],
      {
        hk_id: params[:hk_id],
        apt_ids: params[:appointment_ids_being_declined]
      }
    )
    redirect_to params[:redirect_to]
  end

  def start_working
    ha = current_user.housekeeper_availabilities.on(@date).first_or_initialize
    ha.start_at = Time.current
    ha.save
    ha.track(Location::START_DAY, location_track_params)

    apts = current_user.appointments_on(@date).without_skips.without_hard_breaks
    apts.each do |apt|
      if apt.checklist_tasks.empty?
        Jarvis::Appointment.create_checklist_tasks(apt.customer, apt, @date)
      end
    end

    redirect_to :back
  end

  def end_working
    pending_apt = in_progress_apt
    if pending_apt.present?
      redirect_to appointments_path(date: @date), alert: end_appointment_message(pending_apt, true) and return
    end
    ha = current_user.housekeeper_availabilities.on(@date).first
    ha.end_at = Time.current
    ha.update_attributes(day_rating_params)
    ha.track(Location::END_DAY, location_track_params)

    redirect_to :back
  end

  def send_cannot_service_email_to_customer
    respond_to do |format|
      format.json do
        Jarvis::Controller.refund_and_email_customers_about_appointments_we_cannot_service(params[:apt_ids])
        render :json => {}
      end
    end
  end

  def drop
    apt = Appointment.find_by token: params[:id]
    Housekeeper::Drop.new(apt.housekeeper, nil, apt, params).run!

    if current_user.is_housekeeper?
      redirect_to appointments_path(date: apt.scheduled_at.to_date)
    else
      redirect_to :back
    end
  end

  def pickup
    redirect_to root_path and return unless current_user.is_housekeeper? && current_user.is_active?

    @date, @hk_appointments, @apts_available_for_pickup_by_building = Housekeeper::ExtraAppointments::Service.new(PICK_UP_STRATEGY, current_user, params).list
    @hk = current_user
    @date_dropdowns = Housekeeper::ExtraAppointments::PickUpDates.setup_dropdowns

    render "appointments/housekeeper/pickup"
  end

  def potential_acceptance_times
    respond_to do |format|
      format.json do
        date = parse_text_into_date(params[:date])

        locals = {
          apt_to_pick_up: Appointment.find(params[:apt_to_pick_up]),
          available_slots: Housekeeper::ExtraAppointments::Service.new(PICK_UP_STRATEGY, current_user, params).is_available?,
          hk: current_user
        }

        render :json => {
          potential_slots: (render_to_string partial: "appointments/housekeeper/potential_slots.html.slim", locals: locals, layout: false )
        }
      end
    end
  end

  def pickup_single
    apt = Appointment.find_by_token(params[:id])
    date = apt.scheduled_at.to_date
    redirect_to pickup_appointments_path(date: date), alert: "Sorry, this appointment has already been taken!" and return unless apt.hard_break

    params.merge!({ appointment: apt })
    apt = Housekeeper::ExtraAppointments::Service.new(PICK_UP_STRATEGY, current_user, params).pick_up!
    hk_changed = apt.housekeeper_id_changed?

    if apt.save
      send_notifications_for_changed_appointment(apt) if hk_changed && apt.requires_notifying_customer_of_change?
      redirect_to pickup_appointments_path(date: date), notice: "Appointment successfully picked up"
    else
      redirect_to pickup_appointments_path(date: date), alert: apt.errors.full_messages.to_sentence
    end
  end

  def authorize
    apt = Appointment.find_by_token(params[:id])
    if current_user != apt.customer
      redirect_to FrontEndApp.root_url_auto_login_url(current_user)
    else
      apt.authorized_by_resident = true
      apt.save
      redirect_to FrontEndApp.all_appointments_auto_login_url(apt.customer)
    end
  end

  def decline
    apt = Appointment.find_by_token(params[:id])
    if current_user != apt.customer || apt.started?
      redirect_to FrontEndApp.root_url_auto_login_url(current_user)
    else
      apt.authorized_by_resident = false
      apt.save
      message = revoked_authorization_message(apt)
      Sms.new.run(apt.housekeeper, message)
      redirect_to FrontEndApp.all_appointments_auto_login_url(apt.customer)
    end
  end

  protected

  def appointment_params
    params.require(:appointment).permit(:notes_from_customer,
                                        :rating_from_customer,
                                        :rating_comments_from_customer,
                                        :notes_from_housekeeper,
                                        :rating_from_housekeeper,
                                        :rating_comments_from_housekeeper,
                                        :rating_category_from_housekeeper,
                                        :focus,
                                        :skip,
                                        :housekeeper_id,
                                        :address_id,
                                        :customer_home,
                                        :reason_not_lock
    )
  end

  def owns_appointment(user, appointment)
    user.appointments.include?(appointment)
  end

  def date_appointments
    @appointments = current_user \
                        .appointments \
                        .without_hard_breaks \
                        .authorized_by_resident \
                        .where(:scheduled_at => (@date.beginning_of_day..@date.end_of_day)) \
                        .where("dropped_by is null OR dropped_by <> ?", current_user.id) \
                        .order("scheduled_at asc")
  end

  def day_rating_params
    rate_params = params.require(:day_rating).permit(:rating, :rating_category, :rating_comments)
    if rate_params[:rating].to_i > 3
      rate_params.delete :rating_category
      rate_params.delete :rating_comments
    end
    rate_params
  end

  def merge_general_notes
    data = params['general_notes']
    notes = ""
    notes += "<strong><u>I. PREFERRED METHOD OF COMMUNICATION:</u></strong><br><br>"
    notes += "<strong>- ORDER OF PREFERENCE:</strong> "
    notes += "#{params['preferred_comms_method_1'].blank? ? '(None)' : params['preferred_comms_method_1']}"
    notes += ", #{params['preferred_comms_method_2']}" if params['preferred_comms_method_2'].present?
    notes += ", #{params['preferred_comms_method_3']}" if params['preferred_comms_method_3'].present?

    notes += "<br><br><strong><u>II. CLEANING:</u></strong><br><br>"
    notes += "<div class=\"notes-focus\"><strong>- FOCUS 1:</strong> #{data['focus_1'].blank? ? '(None)' : data['focus_1']}</div>"
    notes += "<div class=\"notes-focus\"><strong>- FOCUS 2:</strong> #{data['focus_2'].blank? ? '(None)' : data['focus_2']}</div>"
    notes += "<div class=\"notes-focus\"><strong>- FOCUS 3:</strong> #{data['focus_3'].blank? ? '(None)' : data['focus_3']}</div>"
    notes += "<div class=\"notes-do-not\"><strong>- DO NOT:</strong> #{data['do_not_1'].blank? ? '(None)' : data['do_not_1']}</div>"
    notes += "<div class=\"notes-do-not\"><strong>- DO NOT:</strong> #{data['do_not_2'].blank? ? '(None)' : data['do_not_2']}</div>"
    notes += "<div class=\"notes-do-not\"><strong>- DO NOT:</strong> #{data['do_not_3'].blank? ? '(None)' : data['do_not_3']}</div>"

    notes += "<br><strong><u>III. SUPPLIES:</u></strong><br><br>"
    notes += "<strong>- ALLERGIES:</strong> #{data['allergies'].blank? ? '(None)' : data['allergies']}<br>"
    notes += "<strong>- PREFERRED CLEANING SUPPLIES:</strong> #{data['cleaning_supplies'].blank? ? '(None)' : data['cleaning_supplies']}<br>"
    notes += "<strong>- CLEANING SUPPLIES STORED:</strong> #{data['supplies_storage'].blank? ? '(None)' : data['supplies_storage']}<br>"
    notes += "<strong>- VACUUM STORED:</strong> #{data['vacuum_storage'].blank? ? '(None)' : data['vacuum_storage']}<br>"
    notes += "<strong>- MOP STORED:</strong> #{data['mop_storage'].blank? ? '(None)' : data['mop_storage']}<br>"

    notes += "<br><strong><u>IV. GENERAL:</u></strong><br><br>"
    notes += "<strong>- NO. BEDROOMS:</strong> #{data['bedrooms'].blank? ? '(None)' : data['bedrooms']}<br>"
    notes += "<strong>- NO. BATHROOMS:</strong> #{data['bathrooms'].blank? ? '(None)' : data['bathrooms']}<br>"
    notes += "<strong>- NO. TOTAL PEOPLE LIVING IN UNIT:</strong> #{data['people_in_unit'].blank? ? '(None)' : data['people_in_unit']}<br>"
    notes += "<strong>- NO. CHILDREN:</strong> #{data['children'].blank? ? '(None)' : data['children']}<br>"
    notes += "<strong>- NO. PETS:</strong> #{data['num_pets'].blank? ? '(None)' : data['num_pets']}<br>"
    notes += "<strong>- NO. TYPE OF PET(S):</strong> #{data['pet_type'].blank? ? '(None)' : data['pet_type']}<br>"
    notes += "<strong>- DAYS WORKING FROM HOME:</strong> #{data['days_from_home'].blank? ? '(None)' : data['days_from_home']}<br>"

    notes += "<br><strong><u>V. OTHER NOTES:</u></strong><br><br>"
    notes += "<strong>- LOCKBOX CODE:</strong> #{data['lockbox_code'].blank? ? '(None)' : data['lockbox_code']}<br>"
    notes += "<strong>- OTHER:</strong> #{data['other'].blank? ? '(None)' : data['other']}<br>"
  end

  def update_trial_pass_end_date(user, appointment, required_date_time)
    # Pretend the consultation was done the day before the required_date_time
    day_before_starter_clean = required_date_time - 1.day
    new_end_date = appointment.trial_end_date(day_before_starter_clean)
    user.latest_pass.update_attributes(
      start_at: day_before_starter_clean,
      end_at: new_end_date
    )
  end

  def check_tos_acceptance
    if current_user.is_housekeeper?
      tos_agreement = TosAgreement.last

      return if tos_agreement.nil?

      accepted_tos_agreements = current_user.tos_acceptances.map(&:tos_agreement)

      if !accepted_tos_agreements.include?(tos_agreement)
        redirect_to tos_summary_path(redirect_to:request.fullpath)
      end
    end
  end

  def furthest_date_to_auto_reassign_drop
    Chronic.parse('next week friday').to_date
  end

  def check_prev_day_status
    prev_day = @date.monday? ? @date - 3.days : @date - 1.days
    availability = current_user.housekeeper_availabilities.on(prev_day).first
    appointment_count = current_user.appointments.scheduled_on(prev_day).without_hard_breaks.without_skips.where("dropped_by is null OR dropped_by <> ?", current_user.id).count
    if availability && appointment_count > 0 && !availability.dropped? && !availability.ended?
      redirect_to appointments_path(date: prev_day), alert: 'Please end working and leave rating.'
    end
  end

  def check_starting_status
    availability = current_user.housekeeper_availabilities.on(@date).first
    appointment_count = current_user.appointments.scheduled_on(@date).without_hard_breaks.where("dropped_by is null OR dropped_by <> ?", current_user.id).count
    if availability && appointment_count > 0 && !availability.dropped? && !availability.started?
      redirect_to appointments_path(date: @date), alert: 'Please start working before move on.'
    end
  end

  def in_progress_apt
    date_appointments.not_blocked.without_skips.detect { |apt| apt.in_progress? }
  end

  def end_appointment_message(appointment, end_day = false)
    message = if end_day
                "You need to end the following appointment before ending work:<br/>"
              else
                "You need to end the following appointment before starting another one:<br/>"
              end
    message += "#{appointment.customer.name}, #{appointment.address.full_address}, #{I18n.l(appointment.timezone_adjusted_scheduled_at, format: :short)}"
    message
  end

  def set_furthest_drop_date
    wednesday_this_week = Chronic.parse('wednesday this week')
    if Time.current.to_date >= wednesday_this_week
      @furthest_drop_date = Chronic.parse('sunday this week') + 1.week
    else
      @furthest_drop_date = Chronic.parse('sunday')
    end
  end

end
