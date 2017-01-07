class SlackPost

  HAPPY_EMOJIS = [":bowtie:", ":kissing_heart:", ":simple_smile:", ":heart:"]
  CONSTRUCTION_EMOJIS = [":construction_worker:", ":construction:"]

  def self.notifier(type)
    case type
    when "improvement"
      webhook = "https://hooks.slack.com/services/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"
    when "payment"
      webhook = "https://hooks.slack.com/services/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"
    when "housekeeper-rating"
      webhook = "https://hooks.slack.com/services/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"
    when "ops-alerts"
      webhook = "https://hooks.slack.com/services/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"
    when "ny-ops-alerts"
      webhook = "https://hooks.slack.com/services/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"
    when "matching"
      webhook = "https://hooks.slack.com/services/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"
    when "user-signup"
      webhook = "https://hooks.slack.com/services/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"
    when "happiness"
      webhook = "https://hooks.slack.com/services/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"
    when "building_operations"
      webhook = "https://hooks.slack.com/services/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"
    end
    if ENV['FAIRY_ENVIRONMENT'] == "production"
      Slack::Notifier.new webhook
    elsif ENV['FAIRY_ENVIRONMENT'] == "staging" || ENV['FAIRY_ENVIRONMENT'] == "api" || Rails.env.development?
      Slack::Notifier.new webhook, http_client: NoOpHTTPClient
    end
  end

  def self.link_formatter(message)
    Slack::Notifier::LinkFormatter.format(message)
  end

  def self.user_signup(user)
    notifier = SlackPost.notifier("user-signup")
    message = "New user created: #{user.name}\n"\
              "#{user.address.full_address}\n"\
              "#{admin_path(user)}"
    message += "\nPromo code: [#{user.promotion_code.code}](#{admin_path(user.promotion_code)})" if user.promotion_code_id
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.consultation_requested(appointment)
    notifier = SlackPost.notifier("consultation")
    user = appointment.address.user
    message = "#{user.name}, from #{appointment.address.full_address}, signed up for a consultation\n[#{appointment.scheduled_at.strftime('%b %d, %Y (%A)')} at #{appointment.scheduled_at.strftime('%l:%M %p')}](#{admin_path(appointment)})"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.housekeeper_rating(appointment)
    notifier = SlackPost.notifier("housekeeper-rating")
    housekeeper = appointment.housekeeper
    customer = appointment.address.user
    message = "#{housekeeper.name} left a [#{appointment.rating_from_housekeeper} star rating](#{admin_path(appointment)}) for #{customer.name} (#{customer.email})\n"\
              ">>> #{appointment.reference_times}\n"\
              "Cleaned for: #{appointment.actual_duration_in_minutes} #{'minute'.pluralize(appointment.actual_duration_in_minutes)}\n"\
              "#{appointment.rating_category_from_housekeeper}\n"\
              "#{appointment.rating_comments_from_housekeeper}"
    message += "\nDid not lock the door. Reason: #{appointment.reason_not_lock}" if appointment.reason_not_lock.present?
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.housekeeper_marked_blocked(appointment)
    notifier = SlackPost.ops_notifier_by_city(appointment.housekeeper.city)
    housekeeper = appointment.housekeeper
    customer = appointment.address.user
    message = "#{housekeeper.name} marked [appointment](#{SlackPost.admin_path(appointment)}) for #{customer.name} (#{customer.email}) as blocked\n"\
              "Blocked Reason: #{appointment.blocked_reason}\n"\
              "Blocked Notes: #{appointment.blocked_notes}"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.housekeeper_ends_service(hk, customer, reason)
    notifier = SlackPost.notifier("matching")
    message  = "#{hk.name} (#{SlackPost.admin_path(hk)}) ends service for #{customer.name} (#{SlackPost.admin_path(customer)}). Reason: #{reason}"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.no_hks_to_choose_from(customer)
    notifier = SlackPost.notifier("matching")
    building = customer.address.building
    message = "New customer [#{customer.name}](#{SlackPost.admin_path(customer)}) in [#{building.name}](#{SlackPost.admin_path(building)}) has no potential HKs to select for primary match"
    if customer.city == City::SAN_FRANCISCO
      message += "\n #{ENV['SF_SUPPLY_TEAM']}"
    elsif customer.city == City::NEW_YORK
      message += "\n #{ENV['NYC_SUPPLY_TEAM']}"
    end
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.payment_info(user, type, user_admin_path, pass_admin_path)
    notifier = SlackPost.notifier("payment")
    pass = user.latest_pass
    if type =="new"
      message = "[#{user.name}](#{user_admin_path}) converted to a paying customer!\nPlan: #{pass.plan.name} (#{pass.plan.duration_per_appointment_in_minutes} min)\nPass: [##{pass.id}](#{pass_admin_path})"
    elsif type == 'trial'
      message = "[#{user.name}](#{user_admin_path}) started trial!\nPlan: #{pass.plan.name} (#{pass.plan.duration_per_appointment_in_minutes} min)\nPass: [##{pass.id}](#{pass_admin_path})"
      message += "\nPromo code: [#{user.promotion_code.code}](#{SlackPost.admin_path(user.promotion_code)})" if user.promotion_code.present?
    else
      message = "[#{user.name}](#{user_admin_path}) renewed for another month!\nPlan: #{pass.plan.name} (#{pass.plan.duration_per_appointment_in_minutes} min)\nPass: [##{pass.id}](#{pass_admin_path})"
    end
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.subscription_changed(user, user_admin_path)
    notifier = SlackPost.notifier("payment")
    pass = user.latest_pass
    message = "[#{user.name}](#{user_admin_path}) changed subscription plans.\nNew Plan: #{pass.plan.name} (#{pass.plan.duration_per_appointment_in_minutes} min)"
    notifier.ping SlackPost.link_formatter(message)
  rescue # do nothing
  end

  def self.payment_failed(user, user_admin_path)
    notifier = SlackPost.notifier("payment")
    message = "WARNING: Credit card failure for: [#{user.name}](#{user_admin_path})"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.housekeeper_no_show(appointments)
    dropped_hks = User.dropped_available_on(Time.current).pluck(:id)

    City::CITIES.each do |city|
      message = "WARNING! #{ENV['SLACK_SUPPORT_TEAM']}\n"
      notifier = SlackPost.ops_notifier_by_city(city)
      city_appointments = appointments.in_city(city)

      next if city_appointments.count == 0

      city_appointments.to_a.group_by(&:housekeeper_id).each do |hk_id, apts|
        hk = User.find hk_id
        next if dropped_hks.include?(hk_id)
        if apts.count > 1
          message += "> [#{hk.name}](#{SlackPost.god_path(hk)}) did not check in #{apts.count} appointments. \n"
          apts.each do |apt|
            message += " > > #{apt.scheduled_at.to_s(:time)} [appointment](#{SlackPost.admin_path(apt)})"
            message += " at #{apt.address.full_address} ([#{apt.address.user.name}](#{SlackPost.god_path(apt.address.user)}))\n" if apt.address
          end
        else
          apt = apts[0]
          message += "> [#{hk.name}](#{SlackPost.god_path(hk)}) did not check into her #{apt.scheduled_at.to_s(:time)} [appointment](#{SlackPost.admin_path(apt)})"
          message += " at #{apt.address.full_address} ([#{apt.address.user.name}](#{SlackPost.god_path(apt.address.user)}))\n" if apt.address
        end
      end
      notifier.ping SlackPost.link_formatter(message)
    end
  rescue => e
    Rollbar.error(e)
  end

  def self.cancel_customer_plan(admin, customer, params = {}, status = :success)
    message = ''
    if admin
      message += ">>> #{admin.name} cancelled #{customer.name}(#{customer.email}) plan."
    else
      message += ">>> Customer #{customer.name} cancelled subscription."
    end
    message += " Subscription ends at #{params[:cancel_date].to_s(:long)}" if params[:cancel_date]
    message += "\n Reason: #{params[:cancelled_reason]}" if params[:cancelled_reason]
    message += "\n Notes: #{params[:cancelled_notes]}" if params[:cancelled_notes]
    message += " \nFailed to cancel on stripe. #{ENV['SLACK_ENG_TEAM']}" if status != :success
    notifier = SlackPost.notifier 'payment'
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.refund_customer(admin, customer, amount, notes, status)
    message = ''
    if status == :success
      if admin
        message += ">>> #{admin.name} refunded $#{amount} to [#{customer.name}](#{SlackPost.admin_path(customer)})."
      else
        message += ">>> $#{amount} refunded to [#{customer.name}](#{SlackPost.admin_path(customer)})."
      end
      message += "\n Notes: #{notes}" if notes
    else
      error_msg = "Not enough balance" if status == :not_enough_balance
      message += ">>> Failed to refund $#{amount} to [#{customer.name}](#{SlackPost.admin_path(customer)}). #{error_msg}. #{ENV['SLACK_ENG_TEAM']}"
    end
    notifier = SlackPost.notifier 'payment'
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_dropped_a_day(hk, date, housekeeper_availability)
    appointments = hk.appointments.scheduled_on(date).without_hard_breaks.without_skips.not_completed
    appointments_count = appointments.count
    drop_reason = appointments.first.try(:drop_reason)
    drop_message_to_customer = appointments.first.try(:drop_message_to_customer)
    availability = "#{appointments_count} #{'appointment'.pluralize(appointments_count)}"

    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = ""
    message += "NOTE: #{hk.name} dropped #{availability} on #{date}.#{' Fear not, Jarvis is working on it!' if appointments_count > 0}"
    message += "\nReason: #{drop_reason}" if drop_reason.present?
    message += "\nNote to Customers: #{drop_message_to_customer}" if drop_message_to_customer.present?
    message += "\n #{ENV['SLACK_SUPPORT_TEAM']} #{ENV['SLACK_ENG_TEAM']}"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_dropped_a_single_appointment(hk, date, apt)
    user = apt.customer
    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = ""
    message += "NOTE: #{hk.name} dropped one appointment on #{date} - [#{user.name}](#{SlackPost.admin_path(user)}) at #{apt.scheduled_at.strftime('%-l:%M %p')}. Fear not, Jarvis is working on it!"
    message += "\nReason: #{apt.drop_reason}" if apt.drop_reason.present?
    message += "\nNote to Customers: #{apt.drop_message_to_customer}" if apt.drop_message_to_customer.present?
    message += "\n #{ENV['SLACK_SUPPORT_TEAM']} #{ENV['SLACK_ENG_TEAM']}"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.drop_or_decline_summary(hk, apts, type)
    date = apts.first.scheduled_at.to_date.strftime("%Y-%m-%d")
    # Using .length instead of .count, which would fetch the apts activerecord call again
    num_appointments = "#{apts.length} #{'appointment'.pluralize(apts.length)}"
    num_hard_breaks = 0
    apts.each do |apt|
      apt.reload
      num_hard_breaks += 1 if apt.hard_break
    end

    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = ""
    message += "Jarvis summary of #{hk.name} #{type.downcase} - #{num_appointments} on #{date}"
    message += "\nReassigned: #{apts.length - num_hard_breaks}"
    message += "\nHard breaks: #{num_hard_breaks}"
    message += "\nCheck the [drops page](#{Rails.application.routes.url_helpers.manage_drops_url(date: date, host: 'magic.itsfairy.com')}) for more details"
    message += "\n #{ENV['SLACK_SUPPORT_TEAM']} #{ENV['SLACK_ENG_TEAM']}"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_not_lock_door(appointment)
    hk = appointment.housekeeper
    notifier = SlackPost.ops_notifier_by_city(appointment.housekeeper.city)
    message = ""
    message += "WARNING! [#{hk.name}](#{SlackPost.admin_path(hk)}) did not lock the door "\
               "for [#{appointment.customer.name}](#{SlackPost.admin_path(appointment.customer)})"\
               " : [appointment](#{SlackPost.admin_path(appointment)})\n"
    message += "Reason: #{appointment.reason_not_lock}"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.new_building_created(building)
    notifier = SlackPost.notifier 'building_operations'
    message = "New building created automatically: #{building.name}(#{SlackPost.admin_path(building)})"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.user_self_signed_up_for_trial_appointment(user, appointment)
    notifier = SlackPost.ops_notifier_by_city(user.city)
    message = "[#{user.name}](#{SlackPost.admin_path(user)}) self signed-up for a trial appointment on "
    message += "[#{appointment.scheduled_at.strftime('%b %d, %Y (%A)')} at #{appointment.scheduled_at.strftime('%l:%M %p')}](#{admin_path(user)})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.user_self_cancels_trial_appointment(user, appointment)
    notifier = SlackPost.ops_notifier_by_city(user.city)
    message = "CANCELLATION: [#{user.name}](#{SlackPost.admin_path(user)}) cancelled a trial appointment on "
    message += "[#{appointment.scheduled_at.strftime('%b %d, %Y (%A)')} at #{appointment.scheduled_at.strftime('%l:%M %p')}](#{admin_path(user)})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.user_preference_service_dates_not_matching_pass(user)
    notifier = SlackPost.ops_notifier_by_city(user.city)
    message = "WARNING: Incorrect number of service days for [#{user.name}](#{SlackPost.admin_path(user)}) based on [latest pass](#{SlackPost.admin_path(user.latest_pass)})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.user_cannot_self_schedule_consultation_or_trial(user)
    notifier = SlackPost.ops_notifier_by_city(user.city)
    message = "WARNING: [#{user.name}](#{SlackPost.admin_path(user)}) cannot schedule consultation or trial"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.cannot_refund_for_missed_appointment(user)
    notifier = SlackPost.notifier("payment")
    message = "We missed an appointment for [#{user.name}](#{SlackPost.admin_path(user)}) but could not refund!"
    notifier.ping SlackPost.link_formatter(message)
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_declined_appointments_day_of(hk, apts_count, date)
    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = "WARNING: [#{hk.name}](#{SlackPost.admin_path(hk)}) declined #{apts_count} #{'appointment'.pluralize(apts_count)} today (#{date.strftime('%B %d, %Y')})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_payment_completed(hk, payment)
    notifier = SlackPost.notifier 'payment'
    message = "Wire transfer for Housekeeper #{hk.name} - #{hk.email} is completed. #{payment.payment_range} - $#{payment.amount}"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.hk_payment_failed(hk, payment)
    notifier = SlackPost.notifier 'payment'
    message = "WARNING: Payment for housekeeper #{hk.name} - #{hk.email} is failed. #{payment.payment_range} - $#{payment.amount}"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.no_potential_hk_available(user, building)
    notifier = SlackPost.notifier 'matching'
    message = "WARNING: No potential matches possible for [#{user.name}](#{SlackPost.admin_path(user)}), who lives at [#{building.name}](#{SlackPost.admin_path(building)})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.same_day_drop_after_deadline(hk, apts)
    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = "WARNING: [#{hk.name}](#{SlackPost.admin_path(hk)}) dropped #{apts.count} #{'appointment'.pluralize(apts.count)} after the same-day deadline."
    apts.each do |apt|
      message += "\n[##{apt.id}](#{SlackPost.admin_path(apt)})"
    end
    if hk.city == City::SAN_FRANCISCO
      message += "\n#{ENV['SF_SUPPLY_TEAM']}"
    elsif hk.city == City::NEW_YORK
      message += "\n#{ENV['NYC_SUPPLY_TEAM']}"
    end
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.match_made(pm)
    notifier = SlackPost.notifier 'matching'
    hk = pm.housekeeper
    customer = pm.customer
    building = customer.address.building
    message = "Huzzah! A match made in heaven: HK [#{hk.name}](#{SlackPost.god_path(hk)})#{'(flex)' if hk.flex} with customer [#{customer.name}](#{SlackPost.god_path(customer)}) in [#{building.name}](#{SlackPost.admin_path(building)})"
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.happiness_delivered(appointment_id)
    appointment = Appointment.find appointment_id
    notifier = SlackPost.notifier 'happiness'
    hk = appointment.housekeeper
    resident = appointment.address.user
    emoji = HAPPY_EMOJIS.sample
    message = "#{hk.first_name} delivered happiness to #{resident.first_name}'s home! #{emoji}"
    notifier.ping message, icon_url: hk.avatar.url(:thumb)
  rescue => e
    Rollbar.error(e)
  end

  def self.improvement_needed(appointment_id)
    appointment = Appointment.find appointment_id
    notifier = SlackPost.notifier 'improvement'
    hk = appointment.housekeeper
    resident = appointment.address.user
    emoji = CONSTRUCTION_EMOJIS.sample
    message = "#{hk.first_name} didn't do a good job in #{resident.first_name}'s home. Needs improvement! #{emoji}\n"
    message += "Feedback for Housekeeper: #{appointment.feedback_for_housekeeper} \n"
    message += "Feedback for Fairy: #{appointment.feedback_for_fairy}\n"
    message += "http://magic.itsfairy.com/manage/appointments/#{(appointment.token)}"
    notifier.ping SlackPost.link_formatter(message), icon_url: hk.avatar.url(:thumb)
  rescue => e
    Rollbar.error(e)
  end

  def self.jarvis_cannot_schedule_trial(user, hk)
    notifier = SlackPost.ops_notifier_by_city(hk.city)
    message = "WARNING: Jarvis could not schedule trial appointments for [#{user.name}](#{SlackPost.admin_path(user)}) with [#{hk.name}](#{SlackPost.admin_path(hk)})"
    if hk.city == City::SAN_FRANCISCO
      message += "\n#{ENV['SF_SUPPLY_TEAM']}"
    elsif hk.city == City::NEW_YORK
      message += "\n#{ENV['NYC_SUPPLY_TEAM']}"
    end
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.dnd_changed(user, dnd)
    notifier = SlackPost.ops_notifier_by_city(user.city)
    action_word = dnd.created_at == dnd.updated_at ? "created a new" : "updated a"
    message = "WARNING: [#{user.name}](#{SlackPost.god_path(user)}) #{action_word} DND"
    if hk.city == City::SAN_FRANCISCO
      message += "\n#{ENV['SF_SUPPLY_TEAM']}"
    elsif hk.city == City::NEW_YORK
      message += "\n#{ENV['NYC_SUPPLY_TEAM']}"
    end
    notifier.ping message
  rescue => e
    Rollbar.error(e)
  end

  def self.admin_path(record)
    "https://magic.itsfairy.com/admin/#{record.model_name.param_key}/#{record.id}"
  end

  def self.god_path(record)
    if record.is_a? User
      if record.is_customer?
        "https://magic.itsfairy.com/manage/customers/#{record.token}"
      else
        "https://magic.itsfairy.com/manage/housekeepers/#{record.token}"
      end
    elsif record.is_a? Appointment
      "https://magic.itsfairy.com/manage/appointments/#{record.token}"
    end
  end

  def self.ops_notifier_by_city(city)
    if city == City::NEW_YORK
      SlackPost.notifier 'ny-ops-alerts'
    else
      SlackPost.notifier 'ops-alerts'
    end
  end

end
