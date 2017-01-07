module UsersHelper

  def week_begin(time)
    time.beginning_of_week.to_date
  end

  def week_end(time)
    time.beginning_of_week.to_date + 4.days
  end

  def current_week
    Time.current
  end

  def next_week
    Time.current + 1.weeks
  end

  def week_after_next
    Time.current + 2.weeks
  end

end