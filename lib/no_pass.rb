class NoPass

  attr_writer :end_at

  def current?
    false
  end

  def stripe_invoice_id
    ""
  end

  def start_at
    end_at
  end

  def end_at
    Time.current.yesterday.to_date
  end

  def plan
    nil
  end

  def save(options)
    nil
  end

end