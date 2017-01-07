task :set_consultations => :environment do

  Address.all.each do |address|
    next if address.no_appointments?
    first_appointment = address.ordered_appointments.first
    first_appointment.update_attributes(consultation: true)
    puts "Set first clean for appointment on #{first_appointment.scheduled_at}"
  end

end

task :restore_consultations => :environment do
  users = [['davesohn@yahoo.com','12:00'],
           ['npshroff@gmail.com','13:30'],
           ['prateek33@gmail.com','08:30'],
           ['daphnelixiao@gmail.com','15:00'],
           ['jcbutts2013@gmail.com','08:00'],
           ['luferbu@gmail.com','07:30'],
           ['tmanand@gmail.com','17:00'],
           ['sara.shirman@gmail.com' ,'17:00'],
           ['ankur@humin.com','11:00'],
           ['vincent.bates@mac.com','17:00'],
           ['gminal510@gmail.com','18:00']]
  morgan = User.find_by email: 'morgan@itsfairy.com'

  users.each do |uu|
    cus = User.find_by email: uu[0]
    if cus.nil?
      puts "#{uu} not found"
      next
    end
    pass = cus.passes.with_deleted.last

    if pass.nil?
      puts "#{uu} pass not found"
      next
    end
    pass.update(deleted_at: nil)

    apt = morgan.appointments.build(
            address_id: cus.address.id,
            scheduled_at: Time.parse("#{Date.today} #{uu[1]}:00 -0700"),
            skip: false,
            consultation: true,
            customer_home: false,
            scheduled_duration_in_minutes: Calendar::MINUTES_PER_CONSULTATION,
            pass_id: pass.id
    )
    apt.save!
  end
end

task generate_tokens: :environment do
  Appointment.with_deleted.where("token is NULL or token = ''").each do |apt|
    apt.token = loop do
      random_token = SecureRandom.urlsafe_base64(nil, false)
      break random_token unless Appointment.exists?(token: random_token)
    end
    apt.save(validate: false)
  end
end

task :fix_jarvis_screwup => :environment do
  CSV.foreach("db/csvs/20160503.csv") do |row|
    apt = Appointment.find_by_id(row[0])
    next if apt.skip
    scheduled_at = row[1]
    soft_break = (row[2] == "FALSE" || row[2] == "nil") ? false : true
    hard_break = (row[3] == "FALSE" || row[3] == "nil") ? false : true
    scheduled_duration_in_minutes = row[4].to_i
    hk_id = row[5].to_i

    apt.update_attributes(
      scheduled_at: parse_text_into_date(scheduled_at),
      soft_break: soft_break,
      hard_break: hard_break,
      scheduled_duration_in_minutes: scheduled_duration_in_minutes,
      housekeeper_id: hk_id
    )
  end
end

task :set_future_within_time_windows_as_blank => :environment do
  Appointment.where("scheduled_at >= ?", Time.current.beginning_of_day + 1.day).update_all(within_time_window: nil)
end

task :reverse_historical_within_time_windows => :environment do
  apts_where_true_ids = Appointment.where(within_time_window: true).pluck(:id)
  apts_where_false_ids = Appointment.where(within_time_window: false).pluck(:id)

  Appointment.where(id: apts_where_true_ids).update_all(within_time_window: false)
  Appointment.where(id: apts_where_false_ids).update_all(within_time_window: true)
end

task :set_within_time_window, [:date] => :environment do |t, args|
  if args.date
    # Make sure date format is YYYY-MM-DD
    zone = "Pacific Time (US & Canada)"
    day = ActiveSupport::TimeZone[zone].parse(args.date)
  else
    day = Time.current.to_date
  end

  Appointment.appointments_on(day).each do |apt|
    if apt.start_at.present? && apt.end_at.present?
      apt.set_within_time_window
      apt.save
    end
  end
end

task :backfill_appointment_authorizations => :environment do
  # Mark past appointments as all one-off authorized
  Appointment.where("scheduled_at < ?", Time.current.beginning_of_day).update_all({
    authorized_by_resident: true,
    authorization_category: Appointment::ONE_OFF
  })

  # Mark future appointments with proper authorization
  Appointment.where("scheduled_at >= ?", Time.current.beginning_of_day).each do |apt|
    apt.set_authorization
    apt.save
  end
end

task :authorize_all_future_appointments => :environment do
  PaperTrail.whodunnit = "One-time mass authorization"
  tomorrow = Time.current.beginning_of_day + 1.day
  Appointment.where("scheduled_at >= ?", tomorrow).not_yet_authorized_by_resident.each do |apt|
    apt.authorized_by_resident = true
    apt.save
  end
end

def parse_text_into_date(date_text)
  # %Y-%m-%d %H:%M:%S
  zone = "Pacific Time (US & Canada)"
  ActiveSupport::TimeZone[zone].parse(date_text)
end
