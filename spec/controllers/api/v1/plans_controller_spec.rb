require 'spec_helper'
require 'rails_helper'

describe Api::V1::PlansController, type: :controller do

  let(:customer) { create(:user, :customer) }
  let(:plan) { create(:plan, :custom_plan) }

  describe "GET #index" do

    before do
      plan
      request.headers["token"] = customer.authentication_token
    end

    it "returns all plan items" do
      raw_response = get :index
      response = JSON.parse(raw_response.body)

      expect(response["plans"].first).to include(
        "name"            => "Custom Plan",
        "stripe_plan_id"  => "custom_plan",
        "price_in_cents"  => 20000,
        "weekly_quantity" => 1
      )
    end

  end

end