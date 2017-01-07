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

describe Api::V1::HousekeepersApi::MessagesController, type: :controller do

  let(:hk_auth_token) { create(:housekeeper_auth_token) }
    let!(:hk) { create(:user, :housekeeper, :san_francisco) }
    let!(:customer) { create(:user, :customer, :san_francisco) }

    before do
      hk_auth_token.update!(user_id: hk.id)
      request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Token.encode_credentials(hk_auth_token.token)

      0.upto(1) do
        post :send_message, { id: customer.id, message: "tst-msg", label: Message::CONVERSATION }
      end
    end

  describe "GET #index" do

    it "should fetch user conversations", :show_in_doc do

      headers = {
        "ACCEPT" => "application/json"
      }

      request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Token.encode_credentials(hk_auth_token.token)

      get :index
      message_item = JSON.parse(response.body).first

      expect(message_item).to include(
        "last_message",
        "recipient"
      )

      expect(message_item['last_message']).to include(
        "id",
        "body",
        "sender_id",
        "label",
        "is_read",
        "created_at"
      )

      expect(message_item['recipient']).to include(
        "id",
        "name",
        "address",
        "avatar"
      )

    end

  end

  describe "GET #show" do

    it "should return conversation bwith recipient", :show_in_doc do
      get :show, id: customer.id
      conversation = JSON.parse(response.body)

      expect(conversation).to include(
        "created_at",
        "recipient",
        "messages"
      )
    end
  end

  describe "POST #send_message" do

    it "should return created message", :show_in_doc do
      post :send_message, { id: customer.id, message: "tst-msg", label: Message::CONVERSATION }

      expect(JSON.parse(response.body)).to include(
        "id",
        "content",
        "label",
        "recipient_id",
        "created_at",
        "is_read",
        "metadata"
      )
    end

  end

  describe "POST #update" do

    it "returns a 204 status code", :show_in_doc do
      post :update, { id: customer.id, last_message_id: Message.last.id }
      expect(response).to have_http_status(204)
    end
  end

end