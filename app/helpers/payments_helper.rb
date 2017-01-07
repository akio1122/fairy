module PaymentsHelper
  def hk_day_payment_detail(day_detail)
    items = []
    if day_detail
      items << day_detail.count_detail
      items << "Neighborhood Changes: #{day_detail.swap_count}, #{number_to_currency(day_detail.swap_amount)}"
      items << "Bonus Amount: #{number_to_currency day_detail.bonus}"
      items << "Tip Amount: #{number_to_currency day_detail.tip}"
      items << "Adjust Amount: #{number_to_currency day_detail.adjust_amount}"
      items << "<strong>Total</strong>: #{number_to_currency day_detail.total}"
      items.reject(&:blank?).join('<br/>')
    else
      ""
    end
  end
end