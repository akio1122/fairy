class CustomPlans::Dulcinea

  DULCINEA_FIVE_DAY = 42900
  DULCINEA_THREE_DAY = 30000

  CUSTOMERS_PLANS = {
    "simon@balchhill.com" => DULCINEA_FIVE_DAY,
    "kuldip@hillyer.cc" => DULCINEA_FIVE_DAY,
    "mayer.niko@icloud.com" => DULCINEA_FIVE_DAY,
    "charles@okito.net" => DULCINEA_FIVE_DAY,
    "heidimurph007@gmail.com" => DULCINEA_FIVE_DAY,
    "jchoi.personal@gmail.com" => DULCINEA_THREE_DAY,
    "jj1111@me.com" => DULCINEA_THREE_DAY,
    "ankur@humin.com" => DULCINEA_THREE_DAY,
    "laraley@me.com" => DULCINEA_FIVE_DAY
  }

  DULCINEA_REFUND_RATE = 40

  def initialize
    @customers = User.where(email: CUSTOMERS_PLANS.keys)
    if @customers.count != CUSTOMERS_PLANS.keys.count
      raise "Dulcinea's customer email changed"
    end
  rescue => e
    Rollbar.error(e)
  end

  def run
    @customers.each do |customer|
      base_rate = customer.plan.price_in_cents
      different_to_charge = CUSTOMERS_PLANS[customer.email] - base_rate
      invoice_item = CreateInvoiceItem.new(customer, different_to_charge, notes).run unless Rails.env.development?
      FinancialTransaction.create_for_charge(customer, different_to_charge / 100, invoice_item, notes)
    end
  end

  def notes
    "Increased rate for Dulcinea"
  end

end
