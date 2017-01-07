class Plan < ActiveRecord::Base

  has_many :passes
  has_many :users

  FIVE_DAY = "5-day"
  THREE_DAY = "3-day"
  TWO_DAY = "2-day"
  ONE_DAY = "1-day"
  PREMIUM_FIVE_DAY = "5-day (P)"
  PREMIUM_THREE_DAY = "3-day (P)"
  TRIAL = "trial"

  SERVICE_DAYS = [ MONDAY = 'mon_service', TUESDAY = 'tue_service', WEDNESDAY = 'wed_service', THURSDAY = 'thu_service', FRIDAY = 'fri_service', SATURDAY = 'sat_service', SUNDAY = 'sun_service']
  STATUSES = [ACTIVE = 'active', PENDING_DISABLED = 'pending_disabled', DISABLED = 'disabled']
  ELIGIBLE_GROUPS = [PREMIUM_GROUP = 'premium', DEFAULT_GROUP = 'default', SINGLE_DAY_GROUP = 'single_day']

  validates :price_in_cents,                      presence: true
  validates :name,                                presence: true
  validates :stripe_plan_id,                      uniqueness: true, allow_nil: true
  validates :city,                                presence: true
  validates :refund_amount_in_cents,              presence: true
  validates :status,                              inclusion: { in: STATUSES }
  validates :weekly_quantity,                     numericality: { only_integer: true }
  validates :duration_per_appointment_in_minutes, numericality: { only_integer: true }, allow_nil: true

  scope :active, -> { where(status: 'active') }
  scope :in_city, -> (city) { where(city: city) }

  def is_paid?
    return self.name==FIVE_DAY || self.name==THREE_DAY || self.name==ONE_DAY
  end

  def is_one_day?
    self.name == ONE_DAY || days_per_week == 1
  end

  def is_two_day?
    self.name == TWO_DAY || days_per_week == 2
  end

  def is_three_day?
    self.name == THREE_DAY || self.name == PREMIUM_THREE_DAY || days_per_week == 3
  end

  def is_five_day?
    self.name == FIVE_DAY || self.name == PREMIUM_FIVE_DAY || days_per_week == 5
  end

  def days_of_week
    days = []
    days << 1 if mon_service
    days << 2 if tue_service
    days << 3 if wed_service
    days << 4 if thu_service
    days << 5 if fri_service
    days << 6 if sat_service
    days << 7 if sun_service
    days
  end

  def refund_rate
    refund_amount_in_cents / 100
  end

  def days_per_week
    days_of_week.count
  end

  def plan_name
    self.name
  end

end
