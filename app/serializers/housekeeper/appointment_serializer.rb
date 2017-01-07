class Housekeeper::AppointmentSerializer < Housekeeper::AppointmentItemBaseSerializer
  include TimeZoneShifter
  attributes :scheduled_at, :completed, :completed_at, :started, :started_at, :blocked, :blocked_at, :skipped, :dropped, :dropped_at, :drop_status
  attributes :housekeeper_has_key, :customer, :tip, :feedback, :address
  has_many :dnd_hours do
    object.customer.do_not_disturb_times.on_same_day_of_week(object.scheduled_at).order(start_time: :asc)
  end

  def address
    AddressSerializer.new(object.address, {
      hide_suite:  anonymize_information?
    })
  end

  def current_time_zone
    object.housekeeper.present? ? object.housekeeper.time_zone.name : City::PST_TIMEZONE
  end

  def scheduled_at
    shifted_time(object.scheduled_at)
  end

  def started
    object.start_at.present?
  end

  def started_at
    shifted_time(object.start_at)
  end

  def completed
    object.completed?
  end

  def completed_at
    shifted_time(object.end_at)
  end

  def blocked
    object.blocked?
  end

  def blocked_at
    shifted_time(object.blocked_at)
  end

  def skipped
    object.skipped?
  end

  def dropped
    object.dropped_at.present? && object.dropped_by == object.housekeeper.id
  end

  def housekeeper_has_key
    object.housekeeper_has_key?
  end

  def customer
    @customer ||= Housekeeper::CustomerSerializer.new(user, { anonymize_information: anonymize_information? })
  end

  def tip
    object.tip_in_cents.to_f / 100.0
  end

  def feedback
    Housekeeper::FeedbackSerializer.new(object).to_h.except(:appointment, :created_at, :scheduled_at) if object.feedback_sentiment.present? || object.rating_from_customer.present?
  end

  class AddressSerializer < ApplicationSerializer
    attributes :zip, :address, :suite, :lat, :lng, :building_id, :building_name

    def lat
      building.try :lat
    end

    def address
      object.address
    end

    def lng
      building.try :lng
    end

    def building_id
      building.try :id
    end

    def building_name
      building.try :name
    end

    def suite
      instance_options[:hide_suite] ? "" : object.suite
    end

    protected
    def building
      @building ||= object.try(:building)
    end
  end

  class DoNotDisturbTimeSerializer < ApplicationSerializer
    attributes :user_id, :start_time, :end_time, :day
  end

  protected
  def user
    @user ||= object.address.user
  end

  private

  def anonymize_information?
    # hide customers full last name and unit number if it is_previous_day
    object.scheduled_at.beginning_of_day < Time.current.beginning_of_day
  end
end
