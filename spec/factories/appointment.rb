FactoryGirl.define do
  factory :appointment do
    focus { Faker::Lorem.paragraph }
    scheduled_duration_in_minutes Calendar::MINUTES_PER_CLEANING
    association :address

    trait :today do
      scheduled_at { Time.current }
    end

    trait :completed do
      start_at { Time.current }
      end_at { Time.current + Calendar::MINUTES_PER_CLEANING.minutes }
    end

    trait :past do
      scheduled_at { Time.current - 1.day }
    end

    trait :future do
      scheduled_at { Time.current + 1.day }
    end

    trait :consultation do
      consultation true
    end

    trait :skip do
      skip true
    end

    trait :dropped do
      dropped_at { Time.current - 1.day }
    end

    trait :blocked do
      blocked_at { Time.current }
    end

    trait :bad_feedback do
      feedback_sentiment { Appointment::BAD_FEEDBACK }
    end

    trait :good_feedback do
      feedback_sentiment { Appointment::GOOD_FEEDBACK }
    end
  end
end
