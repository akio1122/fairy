require 'rails_helper'

RSpec.describe Api::V1::HousekeepersApi::MailboxController, type: :controller do
skip do
  let(:user) { create(:user, :housekeeper) }
  let(:recipient) { create(:user, :customer) }
  let(:housekeeper_auth_token) { create(:housekeeper_auth_token) }


  before do
    user
    housekeeper_auth_token

    0.upto(3) do
      recipient.send_message(user, "tst-msg", recipient.name)
      user.send_message(recipient, "tst-msg", recipient.name)
    end

    request.headers["token"] = user.authentication_token
  end

  describe "GET #inbox" do

    subject {
      raw_response = get :inbox
      response = JSON.parse(raw_response.body)
    }

    it "should have 'inbox' root key" do
      is_expected.to have_key('inbox')
    end

    it "should return inbox conversations" do
     expect(subject['inbox'].any?).to be_truthy
    end

    it "should contain conversation structured hash items" do
      expect(subject['inbox'].first).to include(
        "conversation",
        "last_message",
        "housekeeper_name",
        "housekeeper_id",
        "housekeeper_photo",
        "last_message_sender_name",
        "last_message_sender_photo"
      )
    end

  end

  describe "GET #sent" do

    subject {
      raw_response = get :sent
      response = JSON.parse(raw_response.body)
    }

    it "should have 'sent' root key" do
      is_expected.to have_key('sent')
    end

    it "should return sent conversations" do
     expect(subject['sent'].any?).to be_truthy
    end

    it "should contain conversation structured hash items" do
      expect(subject['sent'].first).to include(
        "conversation",
        "last_message",
        "housekeeper_name",
        "housekeeper_id",
        "housekeeper_photo",
        "last_message_sender_name",
        "last_message_sender_photo"
      )
    end
  end
  end
end
