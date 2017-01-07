module TimeZoneShifter
  def shifted_time(time)
    return nil unless time.present?
    ActiveSupport::TimeZone[current_time_zone].parse time.strftime("%Y-%m-%d %H:%M:%S")
  end
end