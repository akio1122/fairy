require 'rails_helper'

describe Api::V1::ChargesController do
  let(:customer) { create(:user, :customer) }
  let(:customer_with_card) { create(:user, :customer_with_card) }

  describe '#change_card' do
    context 'when user has no existing credit card' do
      before do
        request.headers["TOKEN"] = customer.authentication_token
        @params = {
          card_number: "4242424242424242", # A valid Stripe credit card test number
          card_exp_month: "10", # Arbitrary test data
          card_exp_year: "18",
          card_cvc: "123"
        }
      end

      first_description = 'registers the credit card with Stripe and creates a new card in the Fairy DB'
      it_behaves_like 'a valid change_card response', 'customer', first_description
    end

    context 'when the user has an existing credit card' do
      before do
        request.headers["TOKEN"] = customer_with_card.authentication_token
        @params = {
          card_number: "6011111111111117", # A valid Stripe credit card test number
          card_exp_month: "11", # Arbitrary test data
          card_exp_year: "19",
          card_cvc: "345"
        }
      end

      second_test_description = 'registers the new credit card with Stripe, destroys the existing' +
      ' credit card, and creates the new card in the Fairy DB'

      # it_behaves_like 'a valid change_card response', 'customer_with_card', second_test_description
    end
  end
end
