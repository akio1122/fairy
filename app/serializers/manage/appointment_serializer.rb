class Manage::AppointmentSerializer < ApplicationSerializer
  attributes :scheduled_at, :start_at, :end_at, :blocked_at, :token, :housekeeper_id, :scheduled_duration_in_minutes, :dropped_at
  attributes :hard_break, :skip
  attributes :customer
  has_one :address

  def customer
    @customer ||= UserSerializer.new(user)
  end

  class AddressSerializer < ApplicationSerializer
    attributes :zip, :address, :suite
  end

  protected
  def user
    @user ||= object.address.user
  end
end
