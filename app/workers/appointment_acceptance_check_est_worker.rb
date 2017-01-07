class AppointmentAcceptanceCheckEstWorker
  include Sidekiq::Worker
  include Sidetiq::Schedulable

  sidekiq_options queue: 'critical', retry: false

  schedule_time_zone 'Eastern Time (US & Canada)'

  recurrence do
    weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday).hour_of_day(8)
  end

  def perform(last_occurrence, current_occurrence)
    PaperTrail.whodunnit = "Jarvis Appointment Acceptance Checker (EST)"
    today = Time.current.to_date
    hk_dates_requiring_confirmation = {}

    # Only deal with appointments today or tomorrow
    apts = Appointment.where("scheduled_at >= ? AND scheduled_at <= ?", Time.current.beginning_of_day, (Time.current + 1.day).end_of_day)
    
    apts.without_hard_breaks.requires_housekeeper_confirmation.map do |apt|
      next if !City.in_est?(apt.housekeeper.city)
      hk_dates_requiring_confirmation[apt.housekeeper] ||= []
      date = apt.scheduled_at.to_date
      hk_dates_requiring_confirmation[apt.housekeeper] << date unless hk_dates_requiring_confirmation[apt.housekeeper].include?(date)
    end

    hk_dates_requiring_confirmation.each do |hk, dates|
      dates.each do |date|
        apts = hk.appointments_on(date).requires_housekeeper_confirmation.order(scheduled_at: :asc)
        apt_ids = apts.map(&:id)
        if date == today
          apts.each do |apt| # using .each for version control
            apt.hard_break = true
            apt.save(validate: false)
          end
        else
          options = {
            hk_id: hk.id,
            apt_ids: apt_ids
          }
          Jarvis::Controller.reassign_declined_appointments(date.strftime("%Y-%m-%d"), options)
        end
      end
    end
  end

end