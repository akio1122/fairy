module Manage
  class PaymentsController < BaseController
    before_action :parse_date, only: [:index, :create, :finalize]
    before_action :filter_housekeepers, only: [:index, :create, :finalize]

    def index
      @payment_details = Housekeeper::Payment.new(@date, @housekeepers.pluck(:id))
      @payment_details.run!

      @completed_hks = @housekeepers.select { |hk| @payment_details.transfer_statuses(hk.id).include?(FinancialTransaction::COMPLETED.to_s) }
      @pending_hks = @housekeepers.select { |hk| @payment_details.transfer_statuses(hk.id).include?(FinancialTransaction::PENDING.to_s) }
      @not_submitted_hks = @housekeepers.select { |hk|
        !@payment_details.transfer_statuses(hk.id).include?(FinancialTransaction::PENDING.to_s)  &&
          !@payment_details.transfer_statuses(hk.id).include?(FinancialTransaction::COMPLETED.to_s)
      }
      @completed_amount = @completed_hks.map { |hk| @payment_details.hk_week_total_data(hk.id) }.map(&:total).sum
      @pending_amount = @pending_hks.map { |hk| @payment_details.hk_week_total_data(hk.id) }.map(&:total).sum
      @not_submitted_amount = @not_submitted_hks.map { |hk| @payment_details.hk_week_total_data(hk.id) }.map(&:total).sum

      @unverified_housekeepers = User.housekeepers.without_brand_ambassadors
                                     .includes(:housekeeper_money_account)
                                     .where(housekeeper_money_accounts: {transfers_enabled: [nil, false]})
                                     .order(disabled: :asc).order(first_name: :asc)
                                     .select { |hk| !@payment_details.hk_week_total_data(hk.id).total.zero? }
    end

    def finalize
      @housekeepers = @housekeepers.where(id: params[:housekeeper_id]) if params[:housekeeper_id].present?
      @payment_details = Housekeeper::Payment.new(@date, @housekeepers.pluck(:id), true)
      @payment_details.run!

      @payment_details.finalize!
      redirect_to manage_payments_path(date: @date, filter: params[:filter])
    end

    def create
      @housekeepers = @housekeepers.where(id: params[:housekeeper_id]) if params[:housekeeper_id].present?
      @payment_details = Housekeeper::Payment.new(@date, @housekeepers.pluck(:id))
      @payment_details.run!
      failed = []
      @active_primary_hks = @housekeepers.active_primary.to_a
      @active_flex_hks = @housekeepers.active_flex.to_a
      @active_hks = @housekeepers.active_hks.to_a
      @disabled_hks = @housekeepers.disabled_hks.to_a

      (@active_primary_hks + @active_flex_hks + @active_hks + @disabled_hks).each do |hk|
        transfer = ::HousekeeperTransfer.new(hk, @date, current_user, @payment_details.hk_week_total_data(hk.id).total)
        status = transfer.run
        break if status == :no_balance
        failed.push hk if status == FinancialTransaction::CANCELLED

        if transfer.get_transfer && status != FinancialTransaction::CANCELLED
          @payment_details.submit(hk.id, transfer.get_transfer.id)
        end
      end

      flash[:alert] = "Failed to submit payments to these housekeepers: #{failed.map(&:name).join(', ')}" if failed.count > 0
      redirect_to manage_payments_path(date: @date, filter: params[:filter])
    end

    private

    def filter_housekeepers
      @filter = params[:filter] || 'active_primary'
      @housekeepers = User.send(@filter).order(:first_name)
    end
  end
end
