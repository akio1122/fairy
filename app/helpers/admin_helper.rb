module AdminHelper

  def delayed_appointments(housekeeper)
    first_delayed_appointment = housekeeper.appointments.today.delayed.order("scheduled_at asc").first

    return nil if first_delayed_appointment.nil?

    return {
      first_delay: first_delayed_appointment,
      other_delays: housekeeper.appointments.today.where("scheduled_at > ?", first_delayed_appointment.scheduled_at)
    }
  end

  def rating_for_housekeeper(housekeeper)
    rated_appointments = Appointment.where(housekeeper_id:housekeeper.id) \
                                    .where("rating_from_customer is not null")
    ratings = rated_appointments.average(:rating_from_customer)
    count = rated_appointments.count
    if rated_appointments.present?
      return "#{ratings.round(2)} (#{count})"
    else
      return "N/A"
    end
  end

  def manage_appointment_class(appointment)
    class_name = 'warning' if appointment.rating_from_customer && appointment.poor_rating
    class_name = 'danger' if appointment.skip
    class_name = 'info' if appointment.hard_break
    class_name = 'blocked' if appointment.blocked_at.present?
    class_name
  end

  def manage_rating_class(rating)
    class_name = 'danger' if rating.poor_rating
    class_name = 'success' if rating.rating_from_customer.to_i == 5
    class_name
  end

  def appointment_identifier(appointment)
    customer = appointment.address.user
    hk = appointment.housekeeper
    identifier = ''
    pms = PrimaryMatch.where(housekeeper_id: hk.id, customer_id: customer.id).confirmed.active
    if pms.count > 0
      text = 'PM'
      text += ' (exclusive)' if pms.first.exclusive
      identifier += link_to(text, 'javascript:void(0)', data: {toggle: 'tooltip', placement: 'bottom', title: 'Primary Match'})
    end
    identifier
  end

end
