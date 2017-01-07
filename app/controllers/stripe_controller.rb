class StripeController < ApplicationController
  skip_before_filter  :verify_authenticity_token
  before_action       :get_stripe_object

  def transfer_failed
    transfer = Stripe::Transfer.construct_from @event
    stripe_account_id = @event_json["user_id"]
    if stripe_account_id # transfer from connected account to bank failed
      hma = HousekeeperMoneyAccount.find_by stripe_account_id: stripe_account_id
      hk = hma.user
      pending_payments = hk.financial_transactions.transfers.pending.order(:occurred_at)
      pending_payments.each do |payment|
        payment.update_from_stripe(transfer)
      end

      # disable housekeeper bank transfer
      hma.transfers_enabled = false
      hma.verification_fields_needed = ['bank_account']
      hma.save

      pending_payments.each do |payment|
        SlackPost.hk_payment_failed(hk, payment)
      end
      Sms.new.run(
          hk,
          "Your payment failed to submit to your bank account(#{hma.stripe_bank_account_last_4}): #{transfer.failure_message}"\
          "Please update your bank information or contact support."
      )
    end

    head :ok
  end

  def transfer_created
    transfer = Stripe::Transfer.construct_from @event
    stripe_account_id = @event_json["user_id"]
    if stripe_account_id # transfer from connected account to bank started
      hma = HousekeeperMoneyAccount.find_by stripe_account_id: stripe_account_id
      hk = hma.user
      pending_payments = hk.financial_transactions.transfers.pending.order(:occurred_at)
      pending_payments.each do |payment|
        payment.update_from_stripe(transfer)
      end
    end

    head :ok
  end

  def transfer_paid
    transfer = Stripe::Transfer.construct_from @event
    stripe_account_id = @event_json["user_id"]
    if stripe_account_id # transfer from connected account to bank completed
      hma = HousekeeperMoneyAccount.find_by stripe_account_id: stripe_account_id
      hk = hma.user
      pending_payments = hk.financial_transactions.transfers.pending.order(:occurred_at)
      pending_payments.each do |payment|
        payment.update_from_stripe(transfer)
        Tip.where(housekeeper_transfer_id: transfer.id).update_all(payment_status: Tip::PAID)
        SlackPost.hk_payment_completed(hk, payment)
      end
    end

    head :ok
  end

  def account_updated
    account = HousekeeperMoneyAccount.find_by(stripe_account_id: @event['id'])
    account.update_from_stripe(@event) if account

    head :ok
  end

  def invoice_created
    CreditCustomer.new(Stripe::Invoice.construct_from(@event)).run!
    head :ok
  end

  private

  def get_stripe_object
    @event_json = JSON.parse(request.body.read)
    @event = @event_json['data']['object']
  end
end