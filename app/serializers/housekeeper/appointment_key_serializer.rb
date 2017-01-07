class Housekeeper::AppointmentKeySerializer < ApplicationSerializer
  attributes :token, :group, :name, :resident_name, :in_pocket, :building_id

  def group
    object.address.address
  end

  def name
    object.address.suite
  end

  def resident_name
    "#{object.address.user.first_name} #{object.address.user.last_name}"
  end

  def in_pocket
    object.housekeeper_has_key?
  end

  def checked_in?
    object.key_check_in?
  end

  def checked_out?
    object.key_check_out?
  end

  def building_id
    building.try :id
  end

  protected
  def building
    @building ||= object.address.try(:building)
  end
end
