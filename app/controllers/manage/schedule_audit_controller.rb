module Manage
  class ScheduleAuditController < BaseController

    def index
      @min_ago = params[:min_ago].to_i || 10
      @show_all_versions = params[:show_all_versions] == "true"
      @appointments = Appointment.without_hard_breaks \
                      .without_skips \
                      .not_consultation \
                      .where("updated_at >= ?", Time.current - @min_ago.minutes) \
                      .order("updated_at DESC")
    end

  end
end
