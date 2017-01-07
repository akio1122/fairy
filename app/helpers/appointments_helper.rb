module AppointmentsHelper

  def shifted_time(time_zone_user, time)
    return nil unless time.present?
    ActiveSupport::TimeZone[time_zone_user.time_zone.name].parse time.strftime("%Y-%m-%d %H:%M:%S")
  end

  def average_ratings(appointments)
    avg = appointments.average(:rating_from_customer)
    avg ? avg.round(1) : "N/A"
  end

  def num_ratings(appointments)
    appointments.count(:rating_from_customer)
  end

  def two_hour_range(time)
    "#{time.strftime('%b %d (%A)')}: #{(time - 60.minutes).strftime("%l:%M %p")} - #{(time + 60.minutes).strftime("%l:%M %p")}"
  end

  def display_time_range(appointment)
    # return "" unless appointment.address.user.try(:preference)
    scheduled_at = appointment.timezone_adjusted_scheduled_at
    "#{l(scheduled_at, format: :short)} - #{l(scheduled_at + appointment.appropriate_duration.minutes, format: :short)}"
  end

  def lunch_period(last_appointment)
    Calendar.lunchtime?(last_appointment.scheduled_at + Calendar::MINUTES_PER_CLEANING.minutes + Calendar::MINUTES_BETWEEN_CLEANINGS.minutes)
  end

  def break_period(apt, last_apt)
    apt.scheduled_at - last_apt.scheduled_at > max_interval(apt, last_apt)
  end

  def max_interval(apt, last_apt)
    (last_apt.appropriate_duration + Calendar::MINUTES_BETWEEN_CLEANINGS + WalkingTime.time_between(apt.address.building, last_apt.address.building)) * 60
  end

  def rating_categories_for_housekeepers(is_good=true)
    if !is_good
      return ["I could have gotten more done",
      "It could have been easier to get inside",
      "Resident's notes could have been clearer",
      "The resident could have been less intrusive",
      "The resident could have been more respectful",
      "I'm just not feeling great"].map{|a| [a,a]}

    else
      return ["I got everything done",
      "I got a lot done",
      "Resident's notes were helpful",
      "Resident was helpful in-person",
      "Resident was pleasant in person",
      "I'm just in a good mood"].map{|a| [a,a]}
    end
  end

  def drop_categories_for_housekeepers
    Appointment::VALID_DROP_REASONS
  end

  def newly_added_span
    html = <<-EOS
    <span class="label label-danger">
      Newly Added
    </span>
    EOS
    html.html_safe
  end

  def appointments_customer_names(apts)
    name_array = apts.map(&:address).compact.map(&:user).compact.map(&:first_name).compact
    names = name_array.first(3).join(', ')
    names += ' and more' if name_array.count > 3
    names
  end

  def apts_regular_customer_names(apts)
    customers = User.where(id: apts.joins(:address).pluck('addresses.user_id') & current_user.primary_matches_as_hk.exclusive.pluck(:customer_id)).pluck :first_name
    names = customers.first(3).join(', ')
    names += ' and more' if customers.count > 3
    names
  end

  def appointment_allows_pairing?(appointment)
    customer = appointment.customer
    return !customer.activities.with_category(ActivityCategory::NO_PAIRING).present?
  end

  def appointment_class(appointment)
    'warning bg-warning' if appointment.appropriate_duration > Calendar::MINUTES_PER_CLEANING
  end

  def time_range_class(appointment)
    'text-danger' if appointment.appropriate_duration > Calendar::MINUTES_PER_CLEANING
  end

  def appointment_pay(appointment)
    # only show appointment pay for after today
    if appointment.scheduled_at.to_date >= Time.current.to_date
      hourly = Housekeeper::Rate.get(appointment.housekeeper, appointment.scheduled_at.to_date, appointment.customer, appointment.scheduled_duration_in_minutes)
      if hourly.nil?
        return "N/A"
      else
        pay_per_appointment = hourly * (appointment.scheduled_duration_in_minutes/60.0)
        # return "$#{pay_per_appointment.to_i} for #{appointment.scheduled_duration_in_minutes} mins <br> ($#{hourly.to_i} / hr)".html_safe
        return "$#{pay_per_appointment.to_i} for #{appointment.scheduled_duration_in_minutes} mins".html_safe
      end
    end
  end

  def appointment_pay_in_dollars(apt)
    rate = Housekeeper::Rate.get(apt.housekeeper, apt.scheduled_at.to_date, apt.customer, apt.scheduled_duration_in_minutes)
    rate.present? ? rate / 60.0 * apt.scheduled_duration_in_minutes : 0
  end

  def pay_for_appointments(apts)
    apts.inject(0) {|sum, apt| sum += appointment_pay_in_dollars(apt) }
  end

  def checklist_task_status_labels(task)
    labels = {
      ChecklistTask::NOT_ENOUGH_TIME => "Not Enough Time",
      ChecklistTask::COMPLETED => "Completed Within Time"
    }
    labels[ChecklistTask::COMPLETED_OVER_TIME] = "Completed but took longer than #{task.duration} mins" if task.duration.present?
    labels
  end

  def do_not_disturb_times_display(customer, date)
    dnds = customer.do_not_disturb_times.on_same_day_of_week(date)
    return "" if dnds.empty?
    text = "<strong><i class='fa fa-ban' style='margin-right: 5px;'></i>Do not disturb:</strong><br>"
    dnds.each do |dnd|
      text += "#{dnd.range_in_text}<br>"
    end
    text.html_safe
  end

  def authorization_status(apt)
    if apt.authorized_by_resident
      "<span class='label label-info'>Authorized</span>"
    else
      "<span class='label label-danger'>Needs authorization</span>"
    end
  end

  def backup_slot_detail(slot)
    desc = "#{I18n.l(slot.start_time, format: :short)} ~ #{I18n.l(slot.end_time, format: :short)}"
    desc += ": Min hourly $#{slot.min_hourly_amount}" if slot.min_hourly_amount.to_f > 0.0
    desc
  end
end
