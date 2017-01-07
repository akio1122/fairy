module HousekeeperMethods
  extend ActiveSupport::Concern

  included do
    def end_other_pms(pm)
      customer = pm.customer
      customer.primary_matches.active.pending.update_all(end_at: Time.current)
      customer.primary_matches.active.backups.where(housekeeper_id: pm.housekeeper_id).update_all(end_at: Time.current)
      customer.primary_matches.active.primary.confirmed.where.not(id: pm.id).update_all(end_at: Time.current)
    end

    def hard_break_future_non_primary_appointments(customer, hk)
      PaperTrail.whodunnit = "Change of primary housekeeper"
      future_date = Calendar.end_of_day_after_next_daily_jarvis_run
      customer.appointments.where("scheduled_at > ? AND housekeeper_id <> ?", future_date, hk.id).each do |apt|
        apt.hard_break = true
        apt.save(validate: false)
      end
    end
  end
end