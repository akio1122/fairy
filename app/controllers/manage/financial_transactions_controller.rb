module Manage
  class FinancialTransactionsController < BaseController
    before_filter :set_transaction, only: [:edit, :update, :destroy]

    def new
      @transaction = FinancialTransaction.new
      @transaction.user_id = params[:user_id] if params[:user_id]
    end

    def create
      @transaction = FinancialTransaction.new transaction_params
      if @transaction.save
        redirect_to :back, notice: 'Financial Transaction created!'
      else
        redirect_to :back, alert: "Failed to create financial transaction! - #{@transaction.errors.full_messages.to_sentence}"
      end
    end

    def edit
    end

    def update
      if @transaction.update(transaction_params)
        redirect_to :back, notice: 'Financial Transaction updated!'
      else
        redirect_to :back, alert: "Failed to update financial transaction! - #{@transaction.errors.full_messages.to_sentence}"
      end
    end

    def destroy
      @transaction.destroy
      redirect_to :back, notice: 'Financial Transaction deleted!'
    end

    private

    def set_transaction
      @transaction = FinancialTransaction.find params[:id]
    end

    def transaction_params
      params.require(:financial_transaction).permit(
          :user_id, :amount, :transaction_type, :transaction_method, :transaction_status,
          :occurred_at, :created_by, :modified_by, :appointment_id, :notes, :proof
      )
    end

  end
end
