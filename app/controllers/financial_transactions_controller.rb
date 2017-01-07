class FinancialTransactionsController < ApplicationController

  before_action :authenticate_user!

  def show
    @transaction = current_user.financial_transactions.find params[:id]
    @start_time = @transaction.occurred_at.beginning_of_week.to_date
    @end_time = @transaction.occurred_at.end_of_week.to_date
    @daily_details = current_user.housekeeper_daily_details.where(date: @start_time..@end_time).order(:date)
  end

  def current_week
    @transaction = FinancialTransaction.new(occurred_at: Time.current)
    @payment = Housekeeper::Payment.new(@transaction.occurred_at, [current_user.id])
    @payment.run!
    @start_time = @transaction.occurred_at.beginning_of_week.to_date
    @end_time = @transaction.occurred_at.end_of_week.to_date
    @daily_details = @payment.week_detail(current_user.id)
  end

  def last_week
    @transaction = FinancialTransaction.new(occurred_at: Time.current - 1.weeks)
    @payment = Housekeeper::Payment.new(@transaction.occurred_at, [current_user.id])
    @payment.run!
    @start_time = @transaction.occurred_at.beginning_of_week.to_date
    @end_time = @transaction.occurred_at.end_of_week.to_date
    @daily_details = @payment.week_detail(current_user.id)

    render :current_week
  end

end