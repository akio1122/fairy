module HousekeeperNotification
  extend ActiveSupport::Concern

  included do
    def revoked_authorization_message(apt)
      hk = apt.housekeeper
      customer = apt.customer
      time = apt.scheduled_at.to_date == Time.current.to_date ? "today" : "on #{apt.scheduled_at.strftime('%a, %b %d')}"
      message = "Hi #{hk.name}, one of your substitute appointments #{time}, #{customer.name}, just revoked authorization for entry."
      message += " This happens if residents don't know housekeepers well enough to let them enter their home or won’t be there to meet you."
      message += " No worries, please refresh your schedule to see the updated list of appointments."
    end
  end
end