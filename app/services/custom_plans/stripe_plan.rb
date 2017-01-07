class CustomPlans::StripePlan

  def initialize(plan)
    @plan = plan
  end

  def create_stripe_plan!

    stripe_plan = Stripe::Plan.create(
      amount:   @plan.price_in_cents,
      interval: 'month',
      currency: 'usd',
      id:       get_stripe_id,
      name:     get_stripe_id
    )

    @plan.update!(stripe_plan_id: stripe_plan.id)

  rescue => e
    Rollbar.error(e)
  end

  private

  def get_stripe_id
    [
      @plan.name.parameterize("_"),
      @plan.city.parameterize("_"),
      SecureRandom.hex(10)
    ].join("_")
  end
end