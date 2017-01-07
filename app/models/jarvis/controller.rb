module Jarvis
  class Controller

    MID_WEEK_JARVIS_RUN_HOUR = 21

    def initialize(date, options)
      @date = date
      @options = options
    end

    def self.jarvs_admin
      User.find_by_email("jarvis@itsfairy.com")
    end

    def self.schedule_for(date_string)
      PaperTrail.whodunnit = "Jarvis Main Scheduler"
      # Record the Jarvis run
      date = Time.zone.parse(date_string)
      ja = JarvisActivity.create(task: ::JarvisActivity::GENERAL_RUN_TASK, ran_for: date)
      jarvis_schedule = Jarvis::Schedule.new(date, {})

      # Mark existing appointments as hardbreaks - used only in subsequent runs of the same day
      # Jarvis::Breakage.mark_all_as_hard_breaks(date) if JarvisActivity.already_scheduled_general_run?(date)

      # Schedule users based on primary matches
      jarvis_schedule.schedule_from_primary_matches

      # Fit in users who couldn't get scheduled
      Jarvis::Breakage.assign_missed(date, ::Pass::PAID)
      Jarvis::Breakage.assign_missed(date, ::Pass::TRIAL)

      # Optimize
      # Jarvis::Building.new(date).minimize_building_changes

      # Mark remaining users as hard break
      Jarvis::Breakage.mark_unscheduled_users_as_hard_break(date, ::Pass::PAID)
      Jarvis::Breakage.mark_unscheduled_users_as_hard_break(date, ::Pass::TRIAL)

      # Remove users who shouldn't be scheduled on this day
      Jarvis::Breakage.remove_appointments_not_supposed_to_be_scheduled(date)

      # Record the end of the Jarvis run
      ja.update_attributes(ended_at: Time.current)
    end

    def self.reschedule_to_another_hk(date, options)
      ja = JarvisActivity.create(task: ::JarvisActivity::REASSIGN_TO_ANOTHER_HK, ran_for: date)
      original_hk = User.find(options[:original_hk_id])
      new_hk = User.find(options[:new_hk_id])
      response = Jarvis::Schedule.reschedule_to_another_hk(date, original_hk, new_hk)
      ja.update_attributes(ended_at: Time.current)
      response
    end

    def self.mid_week_schedule(date_string)
      PaperTrail.whodunnit = "Jarvis Daily Scheduler"
      date = Time.zone.parse(date_string)
      ja = JarvisActivity.create(task: ::JarvisActivity::SCHEDULE_WITHIN_AVAILABLE_SLOTS, ran_for: date)
      
      jarvis_schedule = Jarvis::Schedule.new(date, {})
      jarvis_schedule.remove_appointments_no_longer_required

      # Jarvis::Utilities.clean_up_all_hk_buffer_times(date)

      jarvis_schedule.schedule_from_primary_matches
      Jarvis::Breakage.assign_missed(date, ::Pass::PAID)
      Jarvis::Breakage.assign_missed(date, ::Pass::TRIAL)

      # Jarvis::Breakage.remove_appointments_not_supposed_to_be_scheduled(date)
      # Jarvis::Utilities.clean_up_all_hk_buffer_times(date)

      ja.update_attributes(ended_at: Time.current)
    end

    def self.manage_dropped_hk(date_string, options)
      PaperTrail.whodunnit = "Jarvis Drop Manager"
      date = Time.zone.parse(date_string)
      ja = JarvisActivity.create(task: ::JarvisActivity::MANAGE_DROPPED_HK, ran_for: date)
      schedule = Jarvis::Schedule.new(date, options)
      response = schedule.manage_hk_drop
      ja.update_attributes(ended_at: Time.current)
      response
    end

    def self.manage_single_appointment_drop(date_string, options)
      PaperTrail.whodunnit = "Jarvis Single Drop Manager"
      date = Time.zone.parse(date_string)
      ja = JarvisActivity.create(task: ::JarvisActivity::MANAGE_SINGLE_DROPPED_APT, ran_for: date)      
      schedule = Jarvis::Schedule.new(date, options)
      response = schedule.manage_single_appointment_drop
      ja.update_attributes(ended_at: Time.current)
      response
    end

    def optimize
      PaperTrail.whodunnit = "Jarvis Optimizer"
      hk = User.find(@options[:housekeeper_id])

      # Minimize building swaps
      jarvis_building = Jarvis::Building.new(@date)
      jarvis_building.minimize_building_changes_for_hk(hk)

      # Clean up schedule
      Jarvis::Utilities.clean_up_building_change_times_for(hk, @date)
    end

    def self.reassign_declined_appointments(date_string, options)
      PaperTrail.whodunnit = "Jarvis Decline Manager"
      date = Time.zone.parse(date_string)
      ja = JarvisActivity.create(task: ::JarvisActivity::REASSIGN_DECLINED_APPOINTMENTS, ran_for: date)
      schedule = Jarvis::Schedule.new(date, options)
      response = schedule.reassign_declined_appointments
      ja.update_attributes(ended_at: Time.current)
      response
    end

    def self.refund_and_email_customers_about_appointments_we_cannot_service(apt_ids, no_show=false, same_day=false)
      PaperTrail.whodunnit = "Jarvis Hard Break Notifier"
      if apt_ids.any?
        apts = ::Appointment.where(id: apt_ids)
        apts.each do |apt|
          if apt.hard_break_email_sent_at.present? || (same_day && !apt.hard_break)
            apts = apts - [apt]
            next
          end
          original_apt = apt.last_accepted_version
          user = apt.address.user
          refund = RefundCustomer.new(
            Jarvis::Controller.jarvs_admin,
            user,
            apt.refund_amount,
            {
              refund_notes: "Auto-generated: Missed appointment for #{original_apt.scheduled_at.strftime('%B %d, %Y at %-l:%M %p')}"
            }
          )
          if ENV['FAIRY_ENVIRONMENT'] == "production"
            refund_result = refund.run
          else
            refund_result = :success
          end

          if refund_result == :success
            Email.new.customer_cannot_service(original_apt, apt, refund.try(:amount) || 0) unless no_show
          else
            SlackPost.cannot_refund_for_missed_appointment(user)
            Email.new.customer_cannot_service(original_apt, apt, 0) unless no_show
            apt.refund_failed = true
          end

          Email.new.no_show_email_to_customer(user, apt.housekeeper) if no_show

          apt.hard_break_email_sent_at = Time.current
          apt.save(validate: false)
          # Save appointment's pass to update actual_days_serviced
          pass = apt.pass
          if pass
            pass.set_actual_days_serviced
            pass.save
          end
        end
        if apts.any?
          apts_for_email = Jarvis::Utilities.data_for_cannot_schedule_email_to_admin(apts)
          Email.new.cannot_service_summary_to_admin(apts.first.scheduled_at.to_date, apts_for_email)
        end
      end
    end

    def self.schedule_initial_customer_appointments(user)
      PaperTrail.whodunnit = "Jarvis Trial Scheduler"
      ja = JarvisActivity.create(task: ::JarvisActivity::ASSIGN_SINGLE_USER)
      start_date = [user.preference.starter_clean_date, Time.current.to_date + 1.day].compact.max
      schedule = Jarvis::Schedule.new(start_date, {user: user})
      response = schedule.schedule_initial_customer_appointments
      ja.update_attributes(ended_at: Time.current)
      response
    end

  end
end
