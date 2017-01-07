require 'sidekiq/web'
require 'sidetiq/web'

Rails.application.routes.draw do
  default_url_options host: Rails.application.config.domain

  # mount Blazer::Engine, at: "blazer"
  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'

  authenticate :user, lambda { |u| u.is_admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end

  devise_for :users, :controllers => { :registrations => "fairy_registrations",
                                       :passwords => "fairy_passwords" }

  authenticate :user, lambda {|u| u.is_admin? } do
    apipie
  end

  devise_scope :user do
    post '/users/check-availability' => 'fairy_registrations#check_availability', as: :check_availability
  end

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  root 'pages#home'

  get "/housekeeper/android", :to => redirect("#{ENV["HOUSEKEEPER_ANDROID_APP"]}")

  post "update_availability" => "housekeeper_availabilities#update"

  get "my_preferences" => "housekeeper_preferences#my_preferences", as: :my_preferences
  get "my_customers" => "housekeeper_preferences#my_customers", as: :my_customers

  namespace :housekeeper_preferences do
    post :update_building_preferences
    post :confirm_primary_match
    post :decline_primary_match
    post :end_primary_match
    put :update_zone_order
    put :update_building_order
  end

  get "twilio/sms" => "twilio#sms" # sms callback

  resources :housekeeper_money_accounts, only: [:new, :show, :edit, :create, :update, :destroy] do
    member do
      get :new_bank_account
      get :edit_bank_account
      patch :update_bank_account
      post :create_bank_account
      post :remove_bank_account
    end
  end
  resources :financial_transactions, only: [:show] do
    collection do
      get :current_week
      get :last_week
    end
  end

  resources :appointments do
    collection do
      post :decline_availability
      post :confirm_appointments
      post :decline_appointments
      post :start_working
      post :end_working
      post :batch_create
      post "/accept_notes/:customer_id/:housekeeper_id/:appointment_id" => "appointments#accept_notes", as: :accept_notes
      post :send_cannot_service_email_to_customer
      post :backup_confirm
      get :pickup
      get :potential_acceptance_times
    end

    member do
      post :check_in_key
      post :check_out_key
      put :drop
      post :pickup_single
      get :authorize
      get :decline
    end
  end

  # conversations
  resources :conversations do
    member do
      post :reply
      post :trash
      post :untrash
    end
  end

  get "/users/housekeeper_policy" => "users#housekeeper_policy", as: :housekeeper_policy
  get "/users/my_ratings" => "users#my_ratings", as: :my_ratings
  get "/users/pay_statements" => "users#pay_statements", as: :pay_statements
  get "/users/tos_summary" => "users#tos_summary", as: :tos_summary
  get "/users/tos_details" => "users#tos_details", as: :tos_details
  post "/users/accept_tos" => "users#accept_tos", as: :accept_tos
  get "/users/download_app" => "users#download_app", as: :download_app
  get "/account(/:id)" => "users#edit", as: :edit_user
  put "/account/:id" => "users#update", as: :update_user
  get "/invite" => "users#invite", as: :invite
  get "/become" => "admin#become", as: :admin_become
  get "/watcher" => "admin#watcher"
  get "/view_appointment_as_housekeeper" => "admin#view_appointment_as_housekeeper"
  get "/daily_report" => "admin#daily_report", as: :daily_report
  get "/schedule" => "admin#schedule", as: :schedule
  get "/hk_utilization" => "admin#hk_utilization", as: :hk_utilization
  get "/hk_paystubs_list" => "admin#hk_paystubs_list", as: :hk_paystubs_list
  get "/hk_paystubs" => "admin#hk_paystubs", as: :hk_paystubs

  # mailbox folder routes
  get "mailbox/inbox" => "mailbox#inbox", as: :mailbox_inbox
  get "mailbox/sent" => "mailbox#sent", as: :mailbox_sent
  get "mailbox/trash" => "mailbox#trash", as: :mailbox_trash

  get "/concierge/buildings" => "concierge#buildings", as: :concierge_buildings
  get "/concierge/:building_token/appointments" => "concierge#appointments", as: :concierge_appointments
  post "/concierge/:appointment_token/authorize" => "concierge#authorize", as: :concierge_authorize_appointment
  get "/concierge/:building_token/residents" => "concierge#residents", as: :concierge_residents

  get "/breakage" => "admin#breakage", as: :breakage
  post "/remove_hard_breaks_not_requiring_service" => "admin#remove_hard_breaks_not_requiring_service", as: :remove_hard_breaks_not_requiring_service

  resources :charges do
    collection do
      post :invoice_payment_succeeded
      post :invoice_payment_failed
      post :subscription_cancelled
    end
  end

  post '/stripe/transfer-created' => "stripe#transfer_created"
  post '/stripe/transfer-paid' => "stripe#transfer_paid"
  post '/stripe/transfer-failed' => 'stripe#transfer_failed'
  post '/stripe/account-updated' => 'stripe#account_updated'
  post '/stripe/invoice-created' => 'stripe#invoice_created'

  resources :buildings do
    get "/edit-users" => "buildings#edit_users", as: :edit_users
    post "/update-users" => "buildings#update_users", as: :update_users
  end
  post "/manually-update-appointment" => "buildings#manually_update_appointment", as: :manually_update_appointment

  resources :consultation_slots, only: [:index, :create] do
    post "/mark_unavailable" => "consultation_slots#mark_unavailable", as: :mark_unavailable
  end
  resources :checklist_tasks, only: [:update]

  resources :messages, only: [:index, :update, :show] do
    member do
      post '/', action: :send_message
    end
  end

  namespace :manage do
    scope "sms" do
      get "index" => "sms#index"
      post "send_sms" => "sms#send_sms", as: :send_sms
    end

    scope "email" do
      get "index" => "email#index"
      post "send_email" => "email#send_email", as: :send_email
    end

    scope "schedule_template" do
      get "organise"      => "schedule_template#organise"
      get "issues"        => "schedule_template#issues"
      post "save"         => "schedule_template#save"
      post "optimize"     => "schedule_template#optimize"
      post "add-all" => "schedule_template#add_all"
      delete "remove-all" => "schedule_template#remove_all"
    end

    resources :appointment_templates, only: [:create, :destroy]

    resources :neighborhoods, only: [:index, :show] do
      collection do
        post :confirm_primary_match, as: :confirm_primary_match
        post :reject_primary_match, as: :reject_primary_match
        post :create_primary_match, as: :create_primary_match
        post :end_primary_match, as: :end_primary_match
      end
    end
    resources :customers, only: [:index, :show, :update, :destroy] do
      collection do
        post :update_primary_match
        get :checklist_template_task_history_modal
      end
      member do
        delete :refund
      end
    end

    resources :housekeepers, only: [:index, :show, :update] do
      collection do
        post :reassign_primary_matches
        post :admin_block_for_hk
        post :undrop
        get :capacity
      end

      member do
        post :add_building
      end
    end

    resources :buildings, only: [:index, :show, :update]
    resources :zones, only: [:new, :index, :create, :edit, :update, :destroy] do
      post :add_housekeeper, on: :member
      delete :remove_housekeeper, on: :member
    end
    resources :high_risk_flags, only: [:index] do
      post :add_touchpoint, on: :member
      post :complete, on: :member
    end

    resources :jarvis, only: [:index] do
      collection do
        get :stats
        get :building_stats
        get :pm_stats
        get :customer_stats
        get :appointment_stats
        post :create_schedule
        post :mid_week_schedule
        post :reschedule_to_flex
        post "optimize/:housekeeper_id", action: :optimize, as: :optimize
        get :flex
      end
    end

    resources :appointments, only: [:new, :create, :show, :edit, :update] do
      collection do
        get :checklist_task_history_modal
      end
      member do
        post 'restore/:version_id', to: 'appointments#restore', as: :restore
      end
    end
    resources :financial_transactions, only: [:new, :create, :edit, :update, :destroy]

    resources :payments, only: [:index, :create] do
      collection do
        post :finalize
      end
    end
    resources :drops, only: [:index]
    resources :schedule_audit
    resources :locations, only: [:index]
    resources :reports, only: [] do
      collection do
        get :housekeeper
      end
    end
    get "/mom" => "mom#index", as: :mom
    get "/housekeeper/status" => "status#index", as: :status
    get "/housekeeper/status/:apt_token" => "status#show"
    resource :password_reset, only: [:show, :create]

    resources :plans, only: [:index, :new, :create, :edit, :update]
    resources :backup_slots, only: [:index, :new, :create, :edit, :update, :destroy] do
      collection do
        post :duplicate
        put :finalize_all
      end
      put :finalize, on: :member
    end
  end

  namespace :api do
    namespace :v1 do
      scope "general_notes" do
        get  "all" => "general_notes#all"
        post "update" => "general_notes#update"
      end

      resources "checklists" do
        collection do
          post "reorder_checklist_template_task" => "checklists#reorder_checklist_template_task"
          post "reorder_checklist_task" => "checklists#reorder_checklist_task"

          get "template_tasks_for_customer" => "checklists#template_tasks_for_customer"
          get "tasks_for_appointment" => "checklists#tasks_for_appointment"
          post "create_template_task_for_customer" => "checklists#create_template_task_for_customer"
          post "edit_template_task_for_customer" => "checklists#edit_template_task_for_customer"
          delete "remove_template_task_for_customer" => "checklists#remove_template_task_for_customer"
          delete "remove_group_template_tasks_for_customer" => "checklists#remove_group_template_tasks_for_customer"
          get "recommended" => "checklists#recommended"
          post 'complete' => 'checklists#complete'

          post "create_task_for_appointment" => "checklists#create_task_for_appointment"
          put "update_task_for_appointment" => "checklists#update_task_for_appointment"
          delete "delete_task_for_appointment" => "checklists#delete_task_for_appointment"

          post "publish_template_changes_to_future_appointments" => "checklists#publish_template_changes_to_future_appointments"
        end
      end

      scope "addresses" do
        get "/all" => "addresses#all", as: :all_addresses
        get "/check-availability" => "addresses#check_availability", as: :addresses_check_availability
      end

      namespace :housekeepers do
        get :all
        post :set_as_anti_preferred
        delete :remove_as_anti_preferred
        post :create_primary_match
        post :create_multiple_primary_matches
        post :confirm_primary_match
        post :reject_primary_match
        post :set_as_exclusive
        post :create_backup_match
        post :end_backup_match
        get "/:id/reviews", action: :reviews, as: :reviews
        get "/:id", action: :show
      end

      resources :messages, only: [:index, :update, :show] do
        member do
          post '/', action: :send_message
        end
      end

      resources :messages, only: [:index, :update, :show] do
        member do
          post '/', action: :send_message
        end
      end

      namespace :zones do
        get "/:id/housekeepers", action: :housekeepers
        get "/:id/nearby_housekeepers", action: :nearby_housekeepers
      end

      resources :messages, only: [:index, :update, :show] do
        member do
          post '/', action: :send_message
        end
      end

      namespace :housekeepers_api, path: 'hk' do
        resources :auth_tokens, only: [:create, :destroy]
        resources :housekeepers, only: [:show, :update] do
          member do
            get :appointments
            get :payments
            get :customers
            get :feedbacks
            get :keys
            patch :keys, action: :update_keys
            get :availability
            patch :availability, action: :update_availability
            post '/delay_after/:appointment_id', action: :delay_after
            post :start_day
            post :end_day
            get :legal_entity
            get :update_bank_account
            get :my_appointments
            get :update_legal_entity
            patch :password, action: :update_password
            delete :picture, action: :delete_picture
            post :ping
          end
        end

        resources :tos do
          collection do
            get :latest_agreement
            post :accept
          end
        end

        resources :my_customers, only: [:index] do
          member do
            get "profile"
            get "job_request", action: "show_primary_match"
          end

          collection do
            post "job_request/:id/confirm", action: "confirm_primary_match"
            post "job_request/:id/decline", action: "decline_primary_match"
            post "end_service/:id",         action: "end_primary_match"
            post :drop_day
          end
        end

        resources :appointments, only: [:show] do
          member do
            post :override_checklist
            #TODO: deprecated
            post '/resolve_task/:task_id', action: :resolve_task
            #TODO: deprecated
            post :resolve_special_request
            patch :tasks, action: :update_tasks
            post :check_in
            post :check_out
            post :blocked
            post :blocked_by_customer_request
            post :drop
            post :feedback_viewed
            post :reset
          end
          collection do
            get :blocked_reasons
            get :override_checklist_reasons
            get :valid_drop_reasons
            get :pickup
          end
        end

        resources :conversations, only: [:index, :show, :update] do
          member do
            post '/', action: :create_message
          end
        end

        scope "mailbox" do
          get "/inbox" => "mailbox#inbox"
          get "/sent" => "mailbox#sent"
          get "/trash" => "mailbox#trash"
          get "/conversations/with" => "mailbox#conversation_with_customer"
        end

        resources :conversations do
          member do
            post :reply
            post :trash
            post :untrash
          end
        end

        resources :messages, only: [:index, :update, :show] do
          member do
            post '/', action: :send_message
          end
        end

        resources :extra_appointments, only: [:index] do
          get :check_availability, action: :check_availability
          post :pick_up, action: :pick_up
        end

      end

      scope "mailbox" do
        get "/inbox" => "mailbox#inbox"
        get "/sent" => "mailbox#sent"
        get "/trash" => "mailbox#trash"
      end

      resources :conversations do
        member do
          post :reply
          post :trash
          post :untrash
        end
      end

      resources "notification_preferences", only: [:show, :create, :update, :destroy]

      resources :appointments do
        collection do
          scope "available" do
            get "/days" => "appointments#available_days", as: :available_days_for_appointments
          end
          post "/first-session" => "appointments#first_session", as: :first_session
          post "/first-session-email" => "appointments#first_session_email", as: :first_session_email
          get "/all" => "appointments#all", as: :all_appointments
          delete "/cancel" => "appointments#cancel", as: :cancel_appointment
          get "/rating_categories" => "appointments#rating_categories"
          scope "trial" do
            post "/create" => "appointments#create_trial", as: :create_trial
            post "/cannot-schedule" => "appointments#cannot_schedule", as: :cannot_schedule
            delete "/cancel" => "appointments#cancel_trial_appointment", as: :cancel_trial_appointment
          end
          post "/bulk-update" => "appointments#bulk_update", as: :bulk_update
        end

        member do
          post :authorize
          post :decline
          post :leave_feedback
        end
      end

      resources "users" do
        collection do
          get "/show" => "users#show", as: :users_show
          get "/show-user-by-token" => "users#show_user_by_token", as: :users_show_by_token
          post "/signup" => "users#signup", as: :users_signup
          post "/login" => "users#login", as: :users_login
          post "/invite-neighbourhoods" => "users#invite_neighbourhoods", as: :invite_neighbourhoods
          get "/find-referrer" => "users#find_referrer", as: :users_find_referrer
          get "/referrals" => "users#referrals", as: :users_referrals
          get "/check-password" => "users#check_password", as: :users_check_password
          post "/change-password" => "users#change_password", as: :users_change_password
          post "/reset-password" => "users#reset_password", as: :users_reset_password
          post "/recover-password" => "users#recover_password", as: :users_recover_password
          get "/plan" => "users#plan", as: :users_plan
          get "/common-focus-areas" => "users#common_focus_areas", as: :users_common_focus_areas
          post '/credit-card' => 'users#credit_card', as: :user_credit_card
          get "/other-users-in-building" => "users#other_users_in_building", as: :users_other_users_in_building
          post "/send-referral" => "users#send_referral", as: :users_send_referral

          scope 'unsubscribe' do
            delete 'drip-campaign' => "users#unsubscribe_campaign"
          end

          scope "preferences" do
            put "/update" => "users#update_preferences", as: :update_preferences
            post '/key-access-request' => 'users#key_access_request', as: :key_access_request
            post '/key-access-confirm' => 'users#key_access_confirm', as: :key_access_confirm
          end

          resources :do_not_disturb_times, only: [:index, :create, :update, :destroy]
        end
      end

      resources :plans, only: [:index]

      scope "charges" do
        scope "subscription" do
          post "/new" => "charges#new_subscription", as: :new_subscription
          post "/change" => "charges#change_subscription", as: :change_subscription
        end

        scope "card" do
          post "/change" => "charges#change_card", as: :change_card
        end
      end

      scope "general" do
        get "trial_start_dates" => "general#trial_start_dates", as: :trial_start_dates
        get "check_promotion_code" => "general#check_promotion_code", as: :check_promotion_code
        post "send-support-email" => "general#send_support_email", as: :send_support_email
        post "apply_promotion_code" => "general#apply_promotion_code", as: :apply_promotion_code
      end
    end

    match 'v:api/*path', :to => redirect("/api/v1/%{path}"), via: [:get, :post, :put, :delete]
    match '*path', :to => redirect("/api/v1/%{path}"), via: [:get, :post, :put, :delete]
  end

end
