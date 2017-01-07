class AppointmentSerializer < ApplicationSerializer
  attributes :scheduled_at, :customer
  link :self do
    rails_admin_show_path(object)
  end

  def customer
    CustomerSerializer.new(object.address.user).as_json
  end
end