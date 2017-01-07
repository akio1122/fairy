module Jarvis
  class Appointment

    def self.straight_assignment(hk, users, start_time, end_time, starter_clean=false)
      potential_exclusive_users = []
      until users.empty?
        selected_user = users.first

        if hk.dropped_on?(start_time) || !hk.preference.service_on?(start_time) || hk.is_paused_on?(start_time)
          potential_exclusive_users << selected_user
          users = users - [selected_user]
          next
        end

        if Jarvis::Appointment.skip_this_user?(selected_user, start_time, hk)
          users = users - [selected_user]
          next
        end

        start_time += ::Calendar::MINUTES_FOR_LUNCH.minutes if ::Calendar.lunchtime?(start_time) && hk.needs_lunch?(start_time)

        prior_appointment = hk.last_appointment_on(start_time)
        if prior_appointment && Jarvis::Building.change?(selected_user, prior_appointment)
          last_building = prior_appointment.address.building
          building = selected_user.address.building
          start_time += last_building.minutes_to_walk_to_building(building).minutes
        end

        if hk.no_more_time_left(start_time, end_time, selected_user)
          potential_exclusive_users = potential_exclusive_users.concat(users)
          break
        end

        start_time_hash = Jarvis::Appointment.set_appointment(hk, selected_user, start_time, false, starter_clean)
        return start_time_hash[:errors] if start_time_hash[:failure]
        start_time = start_time_hash[:start_time]
        users = users - [selected_user]
      end

      # Set remaining exclusive users as skip
      potential_exclusive_users.each do |user|
        Jarvis::Appointment.set_appointment(hk, user, start_time, true, starter_clean) if user.exclusive_with?(hk)
      end
    end

    def self.set_appointment(hk, selected_user, start_time, hard_break, starter_clean=false)
      latest_pass = selected_user.latest_pass
      return {
        failure: true,
        errors: ["Missing latest pass"]
      } if latest_pass.nil?
      existing_appointment = ::Appointment.not_consultation.appointments_on(start_time).where(address: selected_user.address).first
      appropriate_duration = selected_user.appropriate_duration(start_time, starter_clean)

      if existing_appointment.nil?
        existing_appointment = ::Appointment.new(
          housekeeper: hk,
          scheduled_at: start_time,
          starter_clean: starter_clean,
          scheduled_duration_in_minutes: appropriate_duration,
          address: selected_user.address,
          skip: false,
          pass_id: latest_pass.id
        )
      else
        existing_appointment.assign_attributes(
          housekeeper: hk,
          scheduled_at: start_time,
          starter_clean: starter_clean,
          scheduled_duration_in_minutes: appropriate_duration
        )
      end
      existing_appointment.hard_break = hard_break

      if existing_appointment.hard_break
        existing_appointment.save(validate: false)
      else
        if !existing_appointment.save
          return {
            failure: true,
            errors: existing_appointment.errors.full_messages
          }
        end
      end

      Jarvis::Appointment.create_checklist_tasks(selected_user, existing_appointment, start_time) if existing_appointment.checklist_tasks.empty?

      start_time += appropriate_duration.minutes
      start_time += ::Calendar::MINUTES_BETWEEN_CLEANINGS.minutes
      return {
        start_time: start_time,
        appointment: existing_appointment
      }
    end

    def self.set_skipped_appointment(hk, selected_user, start_time, starter_clean=false)
      existing_appointment = ::Appointment.not_consultation.appointments_on(start_time).where(address: selected_user.address).first
      start_time = existing_appointment.try(:scheduled_at) || Jarvis::Calendar.default_unscheduled_time(start_time)
      starter_clean = selected_user.has_starter_clean_on?(start_time)
      appropriate_duration = selected_user.appropriate_duration(start_time, starter_clean)
      latest_pass = selected_user.latest_pass

      if existing_appointment.nil?
        existing_appointment = ::Appointment.new(
          housekeeper: hk,
          scheduled_at: start_time,
          starter_clean: starter_clean,
          scheduled_duration_in_minutes: appropriate_duration,
          address: selected_user.address,
          pass_id: latest_pass.id,
          skip: true,
          requires_housekeeper_confirmation: false,
          hard_break: false
        )
      else
        existing_appointment.assign_attributes(
          housekeeper: hk,
          scheduled_at: start_time,
          starter_clean: starter_clean,
          scheduled_duration_in_minutes: appropriate_duration,
          skip: true,
          requires_housekeeper_confirmation: false,
          hard_break: false
        )
      end
      existing_appointment.save!
    end

    def self.swap_scheduled_times(apt1, apt2)
      apt1_time = apt1.scheduled_at
      apt2_time = apt2.scheduled_at

      apt1.scheduled_at = apt2_time
      apt1.save

      apt2.scheduled_at = apt1_time
      apt2.save
    end

    def self.create_checklist_tasks(user, appointment, date)
      user.checklist_template_tasks.each do |template_task|
        if template_task.should_do_task_on_date(date)
          ChecklistTask.create(
            appointment: appointment,
            group: template_task.group,
            description: template_task.description,
            notes: template_task.notes,
            duration: template_task.duration,
            sort_order: template_task.sort_order
          )
        end
      end
    end

    def self.skip_this_user?(selected_user, start_time, hk)
      selected_user.appointments_on_without_hard_breaks(start_time).any? ||
      Jarvis::Breakage.breaks_hard_time_rules?(selected_user, start_time) ||
      selected_user.already_dropped_by?(hk, start_time)
    end

  end
end
