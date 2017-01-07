require 'spec_helper'
require 'rails_helper'

describe Api::V1::HousekeepersApi::AuthTokensController, type: :controller do

  let!(:hk) { create(:user, :housekeeper, :san_francisco) }

  it "should generate hk auth token" do
    params = { email: hk.email, password: hk.password }
    headers = { "ACCEPT" => "application/json" }

    post :create, params, headers

    expect(JSON.parse(response.body)['token']).to be_truthy
  end
end

describe Api::V1::HousekeepersApi::ExtraAppointmentsController, type: :controller do

  let(:hk_auth_token) { create(:housekeeper_auth_token) }
  let!(:hk)           { create(:user, :housekeeper, :san_francisco) }
  let!(:customer)     { create(:user, :customer) }
  let!(:address)      { create(:address, user: customer) }
  let!(:appointment)  { create(:appointment,  address: address, housekeeper: hk, hard_break: true, scheduled_at: (Time.current + 2.days + 6.hours)) }
  let!(:appointment1)  { create(:appointment, address: address, housekeeper: hk, hard_break: true, scheduled_at: (Time.current + 1.days + 5.hours)) }

  before do
    hk_auth_token.update!(user_id: hk.id)
    request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Token.encode_credentials(hk_auth_token.token)
  end

  describe "GET #index" do
    it "should return extra appointments within dates diapason", :show_in_doc do
      params = {
        date_from: Time.current.strftime('%d-%m-%Y'),
        date_to:   (Time.current + 5.days).strftime('%d-%m-%Y')
      }

      get :index, params

      appointment_item = JSON.parse(response.body).first

      expect(appointment_item).to include(
        "id",
        "general_notes",
        "scheduled_at",
        "customer",
        "notes_from_customer",
        "cleaning_time",
        "is_picked_up",
        "address",
        "checklist_tasks"
      )
    end
  end

  describe "GET #check_availability" do
<<<<<<< HEAD

=======
>>>>>>> fix_intro_message
    it "should check appointment availability", :show_in_doc do

      get :check_availability, { extra_appointment_id: appointment1.id }

      expect(JSON.parse(response.body)).to include(
        "is_available",
        "message",
        "minutes_walking_between_buildings",
         "scheduled_at"
      )

      expect(JSON.parse(response.body)["is_available"]).to be_truthy

    end
  end

  describe "POST #pick_up" do
    it "should pick up appointment", :show_in_doc do

      get :pick_up, { extra_appointment_id: appointment.id, scheduled_at: Time.current + 1.days }
      expect(JSON.parse(response.body)).to include(
        "message"
      )

      expect(response).to have_http_status(200)

    end

  end

end