module PlansHelper
  def price_in_dollars(plan)
    plan.price_in_cents / 100
  end

  def eligible_groups_list(plan)
    plan.eligible_groups.join(', ')
  end
end