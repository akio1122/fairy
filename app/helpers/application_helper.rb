module ApplicationHelper

  include ScheduleHelper

  def flash_class(name)
    case name
      when "error", 'alert'
        'alert alert-danger'
      else
        'alert alert-info'
    end
  end

  def schedule_appointment_class(appointment)
    class_name = []
    class_name << 'skip' if appointment.skip
    class_name << 'anti-preferred' if appointment.anti_preferred?
    class_name << 'exclusive-match' if appointment.exclusive_match?
    class_name.join(' ')
  end

  def short_url(url)
    Rails.env.development? || Rails.env.test? ? url : Bitly.client.shorten(url).short_url
  end

  def body_class(class_name)
    content_for :body_class, class_name
  end

  def admin_becomed?
    session[:admin_email].present?
  end

  def active_page(active_page)
    @active == active_page ? "active" : ""
  end

end
