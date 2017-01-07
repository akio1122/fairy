module UserNotification
  extend ActiveSupport::Concern

  included do
    def send_notifications_for_changed_appointment(apt)
      return unless apt.requires_notifying_customer_of_change? # Extra fail-safe

      customer = apt.customer
      hk = apt.housekeeper
      primary_hk = customer.primary_housekeeper
      
      authorize_url = Rails.application.routes.url_helpers.decline_appointment_url(apt, auth_token: customer.authentication_token)
      notifications_url = FrontEndApp.manage_notifications_url(customer)

      Email.new.customer_appointment_changed(apt, authorize_url)
      time = apt.scheduled_at.to_date == Time.current.to_date ? "today" : "on #{apt.scheduled_at.strftime('%a, %b %d')}"
      if primary_hk.present?
        message = "Your primary housekeeper #{primary_hk.name_with_last_name_initial} cannot service your home #{time}."
      else
        message = "Your original housekeeper cannot service your home #{time}."
      end
      message += " A substitute housekeeper, #{hk.name_with_last_name_initial}, has agreed to fill in."
      message += " If you would like to revoke authorization for entry for this appointment please click here: #{authorize_url}."
      message += " Note: You can modify your SMS notification preferences here: #{notifications_url}"

      customer.notification_preferences.sms_to_authorize_substitute.each do |np|
        if np.phone.present? && within_appropriate_sms_timeframe?(customer)
          Sms.new.send_directly_to_number(np.phone, message)
        end
      end
    end

    def within_appropriate_sms_timeframe?(customer)
      time = Time.current + City.hours_ahead_of_pst(customer).hours
      time.hour >= 9 && time.hour < 18
    end
  end
end