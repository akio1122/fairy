class Appointment < ActiveRecord::Base
  acts_as_paranoid

  has_paper_trail :only => [
    :housekeeper_id,
    :scheduled_at,
    :skip,
    :start_at,
    :end_at,
    :key_check_in,
    :key_check_out,
    :hard_break,
    :deleted_at,
    :rating_from_customer,
    :rating_from_housekeeper,
    :requires_housekeeper_confirmation,
    :hard_break_email_sent_at,
    :hk_picked_up_at,
    :within_time_window,
    :authorized_by_resident,
    :authorization_category,
    :scheduled_duration_in_minutes
  ]

  include Tokenable
  include AppointmentAdmin
  include Trackable
  include Api

  belongs_to :housekeeper, class_name: User
  belongs_to :dropped_by, class_name: User, foreign_key: "dropped_by"
  belongs_to :address
  has_one :appointment_financial
  has_one :tip, dependent: :destroy
  has_many :checklist_tasks
  belongs_to :pass

  before_validation :ensure_scheduled_duration_in_minutes
  before_save :set_authorization, if: :housekeeper_id_changed?
  before_save :set_feedback_for_housekeeper_created_at!, if: Proc.new { |record|
    record.feedback_for_housekeeper_changed? || record.feedback_sentiment_changed?
  }
  before_save :check_if_requires_housekeeper_confirmation

  validates :address, :housekeeper, presence: true
  validates :scheduled_duration_in_minutes, presence: true
  validate :not_anti_preferred
  validate :not_exclusive_with_different_hk
  # validate :not_overlapping
  validate :user_not_disabled, on: :create
  validate :pet_friendly_match
  validate :within_building_operational_hours, :on => :create
  validate :within_do_not_disturb_times
  validate :hk_in_same_city
  validate :housekeeper_matches_user_auth_level

  scope :today, -> {
    where("scheduled_at between ? and ?", Time.current.beginning_of_day, Time.current.end_of_day)
  }
  scope :not_today, -> {
    where.not("scheduled_at between ? and ?", Time.current.beginning_of_day, Time.current.end_of_day)
  }
  scope :scheduled_on, -> (date) {
    where(scheduled_at: Time.zone.parse(date.to_s).beginning_of_day..Time.zone.parse(date.to_s).end_of_day)
  }
  scope :delayed, -> {
    where("end_at IS NULL AND (scheduled_at + (#{Calendar::MINUTES_PER_CLEANING} * interval '1 minute')) < ?", Time.current)
  }
  scope :start_delayed, -> {
    without_skips.not_consultation.without_hard_breaks.not_started
      .where("scheduled_at < ?", Time.current - 15.minutes)
      .where("scheduled_at > ?", Time.current - 30.minutes)
  }
  scope :started, -> { where.not(start_at: nil) }
  scope :started_after, -> (date) { where("start_at >= ?", date) }
  scope :not_started, -> { where(start_at: nil) }
  scope :started_early, -> { started.not_consultation.where("(scheduled_at - (#{Calendar::MINUTES_ON_TIME_BUFFER} * interval '1 minute')) > start_at") }
  scope :no_key_checkout, -> { started.not_consultation.where(key_check_out: nil) }
  scope :no_key_checkin, -> {
    not_consultation.completed.where(key_check_in: nil).where("(end_at + (#{Calendar::MINUTES_ON_TIME_BUFFER} * interval '1 minute')) < ?", Time.current)
  }
  scope :consultation, -> { where("consultation is true") }
  scope :not_consultation, -> { where("consultation is not true") }
  scope :hard_breaks, -> { where("hard_break is true") }
  scope :without_hard_breaks, -> { where("hard_break is not true") }
  scope :without_skips, -> { where("skip is not true") }
  scope :skipped, -> { where("skip is true") }
  scope :completed, -> { where("end_at is not null") }
  scope :starter_cleanings, -> { without_hard_breaks.where(starter_clean: true) }
  scope :daily_cleanings, -> { without_hard_breaks.where(starter_clean: [nil, false]) }
  scope :with_customer_rating, -> { where.not(rating_from_customer: nil) }
  scope :trials_on, -> (date) {
    not_consultation.without_hard_breaks.without_skips \
    .joins(:address => { :user => :passes }) \
    .where("users.status <> ?", User::PAUSED) \
    .where("scheduled_at >= ? AND scheduled_at <= ?", date.beginning_of_day, date.end_of_day) \
    .where("passes.start_at <= ? AND passes.end_at >= ? AND passes.kind = ?",
      date.to_date, date.to_date, Pass::TRIAL)
  }
  scope :locked, -> { where(lock: true) }
  scope :not_locked, -> { where.not(lock: true) }
  scope :for_payments, -> (range) {
    without_hard_breaks
        .where("appointments.end_at is not null or appointments.blocked_at is not null")
        .where(scheduled_at: range)
  }
  scope :not_completed, -> { where(end_at: nil, blocked_at: nil) }
  scope :on_time, -> {
    completed_on_first_try
    .where(within_time_window: true)
  }
  scope :completed_on_first_try, -> {
    completed
    .not_blocked
    .without_hard_breaks
    .without_skips
  }

  scope :requires_housekeeper_confirmation, -> { where("requires_housekeeper_confirmation is true and confirmed_by_housekeeper_at is null") }
  scope :requires_customer_confirmation, -> { where("requires_customer_confirmation is true and confirmed_by_customer_at is null") }
  scope :not_already_sent_confirmation, -> { where("hard_break_email_sent_at is null") }
  scope :dropped, -> { where.not(dropped_at: nil) }
  scope :picked_up, -> { where.not(hk_picked_up_at: nil) }
  scope :not_picked_up, -> { where(hk_picked_up_at: nil) }
  scope :not_blocked, -> { where(blocked_at: nil) }
  scope :has_rating, -> { where("feedback_sentiment is not null OR rating_from_customer is not null") }
  scope :good_feedback, -> { where("feedback_sentiment = ? OR rating_from_customer >= ?", GOOD_FEEDBACK, 4) }
  scope :bad_feedback, -> { where("feedback_sentiment = ? OR rating_from_customer < ?", BAD_FEEDBACK, 4) }
  scope :authorized_by_resident, -> { where(authorized_by_resident: true) }
  scope :not_yet_authorized_by_resident, -> { where.not(authorized_by_resident: true) }
  scope :one_off_authorizations, -> { where(authorization_category: ONE_OFF) }
  scope :primary_matched, -> { where(authorization_category: PRIMARY_MATCH) }
  scope :in_city, -> (city) { joins(:housekeeper).where("users.city = ?", city) }
  scope :except_not_started, -> { where('start_at is not null or blocked_at is not null or skip is true') }
  scope :in_date_range, -> (range) { where("scheduled_at between ? and ?", range.first.beginning_of_day, range.last.end_of_day) }

  ADDITIONAL_DAYS_FOR_TRIAL = 4

  AUTHORIZATION_CATEGORIES = [
    PRIMARY_MATCH = :primary_match,
    ONE_OFF = :one_off
  ]

  BLOCKED_BY_CUSTOMER_REQUEST = "My customer told me to skip today's appointment"
  BLOCKED_REASONS = [
    "I do not have a key to enter my customer's home",
    "The front desk staff is not here",
    "My customer is not home and I am unable to enter",
    BLOCKED_BY_CUSTOMER_REQUEST,
    "There is a slight pet issue"
  ]

  OVERRIDE_CHECKLIST_REASONS = [
    "Customer left sticky notes",
    "Customer specifically requested I determine what needs to be done",
    "Customer told me via text what to do",
    "Customer told me in-person what do do",
    "Tasks are described in general notes"
  ]

  VALID_DROP_REASONS = [
    "Sick",
    "Transportation Issues",
    "Too Much Travel Between Buildings",
    "No Babysitter",
    "Vacation",
    "Family Emergency"
  ]

  BONUS_AMOUNT_FOR_PICKING_UP_APT_IN_NEW_BUILDING_IN_DOLLARS = 5
  BUFFER_FOR_DAY_OF_PICKUP_IN_HOURS = 1
  HARD_BREAK = "Hard break"
  PENDING_APPROVAL = "Pending approval"
  ACCEPTED = "Accepted"
  GOOD_FEEDBACK = "good"
  BAD_FEEDBACK = "bad"
  HOURS_FOR_DROPS_TO_COUNT_AGAINST_HKS = 48

  WINDOW_EARLIEST_HOUR = 8
  WINDOW_EARLIEST_MIN = 0
  WINDOW_EARLIEST_SECONDS_SINCE_MIDNIGHT = WINDOW_EARLIEST_HOUR * 60 * 60 + WINDOW_EARLIEST_MIN * 60
  WINDOW_LATEST_HOUR = 20
  WINDOW_LATEST_MIN = 0
  WINDOW_LATEST_SECONDS_SINCE_MIDNIGHT = WINDOW_LATEST_HOUR * 60 * 60 + WINDOW_LATEST_MIN * 60
  WINDOW_ROUNDING_INTERVAL_IN_MIN = 30
  WINDOW_SIZE_IN_MIN = 4 * 60
  WINDOW_RADIUS_IN_MIN = WINDOW_SIZE_IN_MIN / 2

  def requires_housekeeper_confirmation?; requires_housekeeper_confirmation==true && confirmed_by_housekeeper_at.nil?; end
  def in_progress?; start_at.present? && end_at.nil?; end
  def completed?; end_at.present?; end
  def started?; start_at.present?; end
  def not_started?; start_at.nil?; end
  def blocked?; blocked_at.present?; end
  def dropped?; dropped_at.present?; end
  def skipped?; !!skip; end
  def is_going_to_be_serviced?; !(blocked? || hard_break || skipped?); end
  def rated_by_customer?; rating_from_customer.present?; end
  def rated_by_housekeeper?; rating_from_housekeeper.present?; end
  def is_rated_bad?; feedback_sentiment==BAD_FEEDBACK; end
  def is_rated_good?; feedback_sentiment==GOOD_FEEDBACK; end

  def start_at
    if self.read_attribute(:start_at).present? && called_from_api?
      self.read_attribute(:start_at) + City.hours_ahead_of_pst(customer).hours
    else
      self.read_attribute(:start_at)
    end
  end

  def end_at
    if self.read_attribute(:end_at).present? && called_from_api?
      self.read_attribute(:end_at) + City.hours_ahead_of_pst(customer).hours
    else
      self.read_attribute(:end_at)
    end
  end

  def calculate_financials
    # revenue
    if self.pass && self.pass.plan
      revenue_in_cents = self.pass.revenue_per_appointment_in_cents
    end

    # expenses
    if self.housekeeper && self.housekeeper.pay_type
      target_hourly_in_cents = self.housekeeper.pay_type.target_hourly_in_cents
      expense_in_cents = target_hourly_in_cents * (self.scheduled_duration_in_minutes / 60.0)
      if self.housekeeper.pay_type.is_employee?
        additional_expense_in_cents = target_hourly_in_cents * (10.0 / 60.0) # overpay for additional 10 mins for now
      end
    end

    if self.appointment_financial.nil?
      self.create_appointment_financial(
        housekeeper_id: self.housekeeper_id,
        revenue_in_cents: revenue_in_cents,
        housekeeper_expense_in_cents: expense_in_cents
      )
    else
      appointment_financial = self.appointment_financial
      appointment_financial.revenue_in_cents = revenue_in_cents
      appointment_financial.housekeeper_expense_in_cents = expense_in_cents
      appointment_financial.additional_expense_in_cents = additional_expense_in_cents
      appointment_financial.save
    end
  end

  def reason_for_no_service
    return nil if is_going_to_be_serviced?

    reason = housekeeper.reason_for_non_schedule(scheduled_at, customer)
    reason = "Customer skipped" if skipped?

    reasons_for_no_service[reason] || 'N/A'
  end

  def reset_state!
    self.class.transaction do
      update({
        start_at: nil,
        end_at: nil,
        key_check_in: nil,
        key_check_out: nil,
        focus_resolved_at: nil,
        override_checklist: false,
        override_checklist_reason: nil
      })

      checklist_tasks.where.not(status: nil).update_all({
        status: nil,
        updated_at: Time.current
      })
    end
  end

  def to_param
    token ? "#{token}" : "#{id}"
  end

  def need_to_accept_notes?
    if address.user.general_notes.nil?
      false
    else
      !accepted_notes?
    end
  end

  def housekeeper_amount
    amount = Housekeeper::Rate.get(
      self.housekeeper,
      self.scheduled_at.to_date,
      self.customer.id,
      self.scheduled_duration_in_minutes
    ) * self.scheduled_duration_in_minutes / 60.0
    amount = amount * 0.5 if self.blocked?
    amount
  end

  def refund_amount
    plan = address.user.plan
    amount = plan.try(:refund_rate).to_f
    # Handle legacy users with 60min plans on old pricing
    if plan.duration_per_appointment_in_minutes != address.user.preference.duration
      amount *= address.user.preference.duration / plan.duration_per_appointment_in_minutes
    end
    amount
  end

  def accepted_notes?
    customer_latest_note == housekeeper_latest_accepted_note
  end

  def customer_latest_note
    address.user.latest_note
  end

  def customer
    address.try(:user)
  end

  def housekeeper_latest_accepted_note
    housekeeper.accepted_notes.where(user: address.user).ordered.last
  end

  def diff_between_notes
    latest_note_content = housekeeper_latest_accepted_note ? housekeeper_latest_accepted_note.content : ""
    Diffy::Diff.new(
      latest_note_content,
      customer_latest_note.try(:content),
      include_plus_and_minus_in_html: true
    ).to_s(:html)
  end

  def trial_end_date(start_date)
    Calendar.business_days_in_the_future(start_date, 5)
  end

  def key_checked_out?
    self.key_check_out.present?
  end

  def key_checked_in?
    self.key_check_in.present?
  end

  def housekeeper_has_key?
    (key_checked_in? && !key_checked_out?) \
      || (key_checked_in? && key_checked_out? && self.key_check_in > self.key_check_out)
  end

  def actual_duration_in_minutes
    ((end_at - start_at) / 60).round(1)
  end

  def poor_rating
    return true if rating_from_customer.nil?
    rating_from_customer <= 3
  end

  def tip_in_cents
    tip.try(:amount_in_cents).to_i
  end

  def tipped?
    tip && tip.amount_in_cents.to_i > 0
  end

  def self.users_on(date)
    User.joins(:address => [:appointments]).where("appointments.hard_break is not true").where("appointments.scheduled_at between ? and ?", date.beginning_of_day, date.end_of_day)
  end

  def self.appointments_on(date)
    Appointment.where("scheduled_at between ? and ?", date.beginning_of_day, date.end_of_day)
  end

  def self.appointments_in_diapason(diapason)
    Appointment.where("scheduled_at between ? and ?", diapason.first.beginning_of_day, diapason.last.end_of_day)
  end

  def self.has_appointments_on(date)
    Appointment.appointments_on(date).any?
  end

  def self.has_non_consultation_appointments_on(date)
    Appointment.not_consultation.appointments_on(date).any?
  end

  def limited_checklist_tasks
    duration_limit = 0
    total_minutes = self.scheduled_duration_in_minutes.to_i
    tasks = checklist_tasks.sorted
    selected = []
    tasks.each do |task|
      duration_limit += task.duration.to_i
      duration_limit <= total_minutes ? selected << task : break
    end
    ChecklistTask.where(id: selected.map(&:id))
  end

  def appropriate_duration
    return 0 if address.nil?
    return scheduled_duration_in_minutes if scheduled_duration_in_minutes
    preference = address.user.preference
    if starter_clean
      return Calendar::MINUTES_PER_STARTER_CLEAN if preference.nil?
      preference.starter_clean_duration
    else
      return Calendar::MINUTES_PER_CLEANING if preference.nil?
      preference.duration
    end
  end

  # Slack post date string
  def reference_times
    dates = []
    dates << "Scheduled At: #{scheduled_at.to_s(:long)}" if scheduled_at.present?
    dates << "Serviced: #{start_at.to_s(:time)} ~ #{end_at.to_s(:time) if completed?}" if start_at.present?
    dates.join(', ')
  end

  def scheduled_in_the_future?
    scheduled_at > Time.current.end_of_day
  end

  def scheduled_end_time
    scheduled_at + appropriate_duration.minutes
  end

  def anti_preferred?
    return false if address.nil? || address.user.nil?
    address.user.anti_preferred_housekeepers.pluck(:id).include? housekeeper_id
  end

  def exclusive_match?
    PrimaryMatch.active.confirmed.exclusive.where(customer_id: customer.id, housekeeper_id: housekeeper_id).count > 0
  end

  def last_accepted_version
    previous_apt = self.previous_version
    return self if previous_apt.nil?
    until previous_apt.nil? || !previous_apt.requires_housekeeper_confirmation
      previous_apt = previous_apt.previous_version
    end
    return self if previous_apt.nil?
    previous_apt
  end

  def is_first_appointment?
    self == customer.appointments.first || starter_clean
  end

  def last_appointment(&block)
    scope = address.appointments.where('scheduled_at < ?', DateTime.now)
    scope = yield scope if block_given?
    scope.order(created_at: :desc).limit(1).first
  end

  def timezone_adjusted_scheduled_at
    return scheduled_at if address.nil? || address.user.nil?
    scheduled_at + City.hours_between_cities(housekeeper.city, address.user.city).hours
  end

  def drop_status
    if hard_break
      HARD_BREAK
    elsif confirmed_by_housekeeper_at.present?
      "#{ACCEPTED} by #{housekeeper.name}"
    elsif requires_housekeeper_confirmation
      PENDING_APPROVAL
    end
  end

  def self.remove_future_appointments_on_non_preferred_days(user)
    user.future_appointments.not_today.where("extract(dow from scheduled_at) NOT IN (?)", user.plan.days_of_week).destroy_all
  end

  def self.count_num_primary_matches(apts)
    apts.inject(0) do |sum, apt|
      if apt.customer.primary_matches.active.confirmed.map(&:housekeeper).include?(apt.housekeeper)
        sum += 1
      else
        sum
      end
    end
  end

  def primary_matched?
    authorization_category.to_sym == PRIMARY_MATCH
  end

  def time_window_times
    # 4-hour windows, 8am-8pm max or the housekeeper's start/end if that is a larger range
    # Normal setup, no restrictions
    rounded_time = Calendar.round_off(scheduled_at, WINDOW_ROUNDING_INTERVAL_IN_MIN.minutes)
    start_time = rounded_time - WINDOW_RADIUS_IN_MIN.minutes
    end_time = rounded_time + WINDOW_RADIUS_IN_MIN.minutes

    # See what's earlier - default start or housekeeper start; take the earlier
    upper_bound = [
      WINDOW_EARLIEST_SECONDS_SINCE_MIDNIGHT,
      housekeeper.preference.start_on(scheduled_at).seconds_since_midnight,
    ].compact.min

    # If there's a previous DND binding the upper bound, take the end time of the DND
    upper_bound = [
      upper_bound,
      previous_dnd.try(:end_time).try(:seconds_since_midnight)
    ].compact.max

    upper_bound_time = scheduled_at.beginning_of_day + upper_bound.seconds

    # See what's later - default end or housekeeper end; take the later
    lower_bound = [
      WINDOW_LATEST_SECONDS_SINCE_MIDNIGHT,
      housekeeper.preference.end_on(scheduled_at).seconds_since_midnight,
    ].compact.max

    # If there's a subsequent DND binding the lower bound, take the start time of the DND
    lower_bound = [
      lower_bound,
      next_dnd.try(:start_time).try(:seconds_since_midnight)
    ].compact.min

    lower_bound_time = scheduled_at.beginning_of_day + lower_bound.seconds

    # If default start time is earlier than upper bound, change start time to upper bound and modify end time
    if start_time.seconds_since_midnight < upper_bound
      start_time = start_time.change(hour: upper_bound_time.hour, min: upper_bound_time.min)
      end_time = [(start_time + WINDOW_SIZE_IN_MIN.minutes), lower_bound_time].min
    end

    # If default end time is later than lower bound, change end time to lower bound and modify start time
    if end_time.seconds_since_midnight > lower_bound
      end_time = start_time.change(hour: lower_bound_time.hour, min: lower_bound_time.min)
      start_time = [(end_time - WINDOW_SIZE_IN_MIN.minutes), upper_bound_time].max
    end

    [start_time, end_time]
  end

  def time_window
    start_time, end_time = time_window_times
    "#{start_time.strftime('%-l:%M %p')} - #{end_time.strftime('%-l:%M %p')}".gsub(":00", "")
  end

  def time_window_with_date
    "#{scheduled_at.strftime('%b %-d')}, #{time_window}"
  end

  def next_dnd
    dnds = customer.do_not_disturb_times.on_same_day_of_week(scheduled_at).sort_by{|dnd| dnd.start_time.seconds_since_midnight}
    dnds.each do |dnd|
      return dnd if dnd.start_time.seconds_since_midnight > scheduled_end_time.seconds_since_midnight
    end
    return nil
  end

  def previous_dnd
    dnds = customer.do_not_disturb_times.on_same_day_of_week(scheduled_at).sort_by{|dnd| dnd.end_time.seconds_until_end_of_day}
    dnds.each do |dnd|
      return dnd if scheduled_at.seconds_since_midnight > dnd.end_time.seconds_since_midnight
    end
    return nil
  end

  def set_within_time_window
    upper_bound, lower_bound = time_window_times
    self.within_time_window = start_at >= upper_bound && end_at <= lower_bound
  end

  def start_or_end_within_do_not_disturb?
    customer.do_not_disturb_at?(scheduled_at) || customer.do_not_disturb_at?(scheduled_end_time)
  end

  def start_or_end_within_do_not_disturb_at?(datetime)
    customer.do_not_disturb_at?(datetime) || customer.do_not_disturb_at?(datetime + scheduled_duration_in_minutes.minutes)
  end

  def set_authorization
    if customer.primary_housekeeper == housekeeper
      self.authorized_by_resident = true
      self.authorization_category = PRIMARY_MATCH
    elsif not_automatically_authorized?
      self.authorized_by_resident = false
      self.authorization_category = ONE_OFF
    else
      self.authorized_by_resident = true
      self.authorization_category = ONE_OFF
    end
  end

  def problem_status_with_primary
    if primary_matched? && !hard_break
      "All good"
    else
      if primary_matched?
        housekeeper.reason_for_non_schedule(scheduled_at, customer)
      elsif customer.primary_housekeeper.present?
        customer.primary_housekeeper.reason_for_non_schedule(scheduled_at, customer)
      else
        "Customer has no primary match"
      end
    end
  end

  def not_automatically_authorized?
    (customer.preference.primary_only? && customer.primary_housekeeper != housekeeper) ||
    (customer.preference.primary_or_backups_only? && !customer.matched_with?(housekeeper))
  end

  def requires_notifying_customer_of_change?
    serviceable? &&
    customer.preference.notify_unless_primary_or_backups? &&
    !customer.matched_with?(housekeeper)
  end

  def serviceable?
    !hard_break && !skip && !blocked? && authorized_by_resident
  end

  def fitting_pass
    pass = customer.passes.where("start_at <= ? AND end_at >= ?", scheduled_at, scheduled_at).first
    pass = customer.latest_pass if pass.nil?
    pass
  end

  private

  def reasons_for_no_service
    date = scheduled_at.strftime('%A, %D')
    hk_name = housekeeper.name
    explanation_root = "Your primary Fairy housekeeper, #{hk_name}, "

    {
      "Primary dropped" => explanation_root + "cancelled your cleaning appointment for #{date}.",
      "Primary self-scheduled off" => explanation_root + "is unable to work #{date}.",
      "Primary doesn't work this day" => explanation_root + "does not work on #{date}.",
      "Primary on pause" => explanation_root + "is on vacation for #{date}",
      "Primary schedule full" => "We were unable to schedule your primary housekeeper, #{hk_name}, for #{date}.",
      "Potential DND conflict" =>
        "The housekeeper #{hk_name} may only have been available during your Do Not Disturb hours for #{date}.",
      "Primary schedule open but could not schedule" =>
        "We were unable to schedule #{hk_name} for #{date}.",
      "Exclusive match unavailable" => "Your exclusive Fairy housekeeper, #{hk_name}, is " +
        "unavailable on #{date}.",
      "Customer skipped" => "You have chosen to skip your appointment for #{date}."
    }
  end

  def set_feedback_for_housekeeper_created_at!
    self.feedback_for_housekeeper_created_at = Time.current
  end

  def ensure_scheduled_duration_in_minutes
    if scheduled_duration_in_minutes.nil?
      if starter_clean
        self.scheduled_duration_in_minutes = Calendar::MINUTES_PER_STARTER_CLEAN
      else
        self.scheduled_duration_in_minutes = Calendar::MINUTES_PER_CLEANING
      end
    end
  end

  def not_anti_preferred
    user = address.user
    if user.anti_preferred_housekeepers.include?(housekeeper)
      errors.add(:housekeeper_id, "#{housekeeper.name} is anti-preferred by #{user.name}")
    end
  end

  def not_exclusive_with_different_hk
    user = address.user
    exclusive_hk = user.exclusive_hk
    if exclusive_hk && exclusive_hk != housekeeper
      errors.add(:base, "Customer #{user.name} exclusively prefers HK #{exclusive_hk.name}")
    end
  end

  def not_overlapping
    overlapping_appointments = Appointment.without_hard_breaks \
                               .without_skips \
                               .not_consultation \
                               .where(housekeeper: housekeeper) \
                               # Adding one second to the scheduled_at because the top end of the range is inclusive
                               .where(scheduled_at: (scheduled_at + 1.second)...(scheduled_at + scheduled_duration_in_minutes.minutes)) \
                               .where.not(address_id: address_id) \

    if overlapping_appointments.any?
      errors.add(:scheduled_at, "overlaps with another appointment for #{housekeeper.name}")
    end
  end

  def user_not_disabled
    if address.user.is_disabled?
      errors.add(:base, "#{address.user.name} is disabled")
    end
  end

  def pet_friendly_match
    if housekeeper_id_changed? && address.user.has_pet? && !housekeeper.preference.pet
      errors.add(:base, "#{address.user.name} has a pet, but #{housekeeper.name} is afraid of pets!")
    end
  end

  def within_building_operational_hours
    if address.building.outside_of_open_hours?(scheduled_at)
      errors.add(:base, "Appointment must be within building's operational hours (building: #{address.building.name})")
    end
  end

  def within_do_not_disturb_times
    if start_or_end_within_do_not_disturb?
      errors.add(:base, "Appointment period cannot overlap customer's do not disturb hours")
    end
  end

  def hk_in_same_city
    if housekeeper.city != customer.city
      errors.add(:housekeeper_id, "must be in the same city as the customer")
    end
  end

  def check_if_requires_housekeeper_confirmation
    if customer.matched_with?(housekeeper)
      self.requires_housekeeper_confirmation = false
      nil # Required so we don't trigger ActiveRecord::RecordNotSaved - http://apidock.com/rails/ActiveRecord/RecordNotSaved
    end
  end

  def housekeeper_matches_user_auth_level
    if !customer.meets_auth_level_requirements?(housekeeper)
      errors.add(:housekeeper_id, "cannot be assigned based on the customer's authorization level")
    end
  end

end
