module AppointmentAdmin
  extend ActiveSupport::Concern

  included do
    rails_admin do
      field :id
      field :housekeeper do
        associated_collection_scope do
          Proc.new { |scope|
            scope = scope.where(role: "housekeeper")
          }
        end
      end
      field :address do
        associated_collection_scope do
          Proc.new { |scope|
            scope = scope.joins(:user).merge(User.customers.active)
          }
        end
        searchable :address
      end
      field :pass
      field :scheduled_at
      field :start_at
      field :end_at
      field :focus
      field :consultation
      field :starter_clean
      field :lock
      field :skip
      field :within_time_window
      field :hard_break
      field :scheduled_duration_in_minutes
      field :customer_home
      field :rating_from_customer
      field :rating_category_from_customer
      field :rating_comments_from_customer
      field :blocked_at
      field :blocked_reason
      field :blocked_notes
      field :refund_failed

      object_label_method do
        :admin_label
      end
    end

    def admin_label
      "##{id} - #{scheduled_at.try(:to_s, :short)}"
    end
  end
end