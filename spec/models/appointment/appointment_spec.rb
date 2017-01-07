require "rails_helper"

describe "Appointment" do
  let(:customer) { create(:user, :customer, :san_francisco) }
  let(:building) { create(:building) }
  let(:address) { create(:address, building: building, user: customer) }
  let(:hk) { create(:user, :housekeeper, :san_francisco) }
  let(:hk2) { create(:user, :housekeeper, :san_francisco) }
  let(:preference) { create(:preference, :default_hk, user: hk) }
  let!(:appointment1) { create(:appointment, :future, housekeeper: hk, address: address, scheduled_at: Time.current.change(hour: 13, min: 14, sec: 0)) }
  let!(:appointment2) { create(:appointment, :future, housekeeper: hk, address: address, scheduled_at: Time.current.change(hour: 8, min: 0, sec: 0)) }
  let!(:appointment3) { create(:appointment, :future, housekeeper: hk, address: address, scheduled_at: Time.current.change(hour: 20, min: 0, sec: 0)) }
  let!(:appointment4) { create(:appointment, :future, housekeeper: hk, address: address, scheduled_at: Time.current.change(hour: 13, min: 16, sec: 0)) }
  let!(:appointment5) { create(:appointment, :future, housekeeper: hk, address: address, scheduled_at: Time.current.change(hour: 9, min: 0, sec: 0)) }
  let!(:pm) { create(:primary_match, :confirmed, customer: customer, housekeeper: hk) }

  context "#time_window" do

    context "rounds" do

      it "down to closest 30 min" do
        expect(appointment1.time_window).to eq("11 AM - 3 PM")
      end

      it "up to closest 30 min" do
        expect(appointment4.time_window).to eq("11:30 AM - 3:30 PM")
      end

    end

    context "with early HK start or late HK end" do

      before do
        day_of_week = Time.current.strftime("%a").downcase
        preference.send("#{day_of_week}_start=", Time.current.change(hour: 7, min: 0, sec: 0)) 
        preference.send("#{day_of_week}_end=", Time.current.change(hour: 21, min: 0, sec: 0)) 
      end

      it "does not start before HK starts" do
        expect(appointment2.time_window).to eq("7 AM - 11 AM")
      end

      it "does not end after HK ends" do
        expect(appointment3.time_window).to eq("5 PM - 9 PM")
      end

    end

    context "without unusual HK start / end" do

      it "does not start before 8 AM" do
        expect(appointment2.time_window).to eq("8 AM - 12 PM")
      end

      it "does not end after 8 PM" do
        expect(appointment3.time_window).to eq("4 PM - 8 PM")
      end

    end

    context "with limiting DND" do

      context "before appointment" do

        before do
          DoNotDisturbTime.create(
            start_time: Time.current.change(hour: 8, min: 0, sec: 0),
            end_time: Time.current.change(hour: 8, min: 30, sec: 0),
            day: appointment5.scheduled_at.strftime("%A"),
            user: customer
          )
        end

        it "does not start before DND end time" do
          expect(appointment5.time_window).to eq("8:30 AM - 12:30 PM")
        end

      end

      context "after appointment" do

        before do
          DoNotDisturbTime.create(
            start_time: Time.current.change(hour: 11, min: 30, sec: 0),
            end_time: Time.current.change(hour: 12, min: 0, sec: 0),
            day: appointment2.scheduled_at.strftime("%A"),
            user: customer
          )
        end

        it "does not end after DND start time" do
          expect(appointment2.time_window).to eq("8 AM - 11:30 AM")
        end

      end

      context "before and after appointment" do

        before do
          DoNotDisturbTime.create(
            start_time: Time.current.change(hour: 8, min: 0, sec: 0),
            end_time: Time.current.change(hour: 8, min: 30, sec: 0),
            day: appointment5.scheduled_at.strftime("%A"),
            user: customer
          )
          DoNotDisturbTime.create(
            start_time: Time.current.change(hour: 11, min: 30, sec: 0),
            end_time: Time.current.change(hour: 12, min: 0, sec: 0),
            day: appointment5.scheduled_at.strftime("%A"),
            user: customer
          )
        end

        it "does not end after DND start time" do
          expect(appointment5.time_window).to eq("8:30 AM - 11:30 AM")
        end

      end

    end

  end

  context "#within_do_not_disturb_times" do

    before do
      DoNotDisturbTime.create(
        start_time: Time.current.change(hour: 13, min: 0, sec: 0),
        end_time: Time.current.change(hour: 14, min: 0, sec: 0),
        day: appointment1.scheduled_at.strftime("%A"),
        user: customer
      )
    end

    it "does create outside of DND" do
      apt_count = Appointment.count
      apt = appointment2.dup
      apt.save
      expect(Appointment.count).to eq(apt_count + 1)
    end

    it "does not create within DND" do
      apt_count = Appointment.count
      apt = appointment1.dup
      apt.save
      expect(Appointment.count).to eq(apt_count)
    end

  end

  context "#serviceable?" do

    context "hard break" do

      it "true" do
        appointment1.update(hard_break: false)
        expect(appointment1.serviceable?).to eq(true)
      end

      it "false" do
        appointment1.update(hard_break: true)
        expect(appointment1.serviceable?).to eq(false)
      end

    end

    context "skip" do

      it "true" do
        appointment1.update(skip: false)
        expect(appointment1.serviceable?).to eq(true)
      end

      it "false" do
        appointment1.update(skip: true)
        expect(appointment1.serviceable?).to eq(false)
      end

    end

    context "blocked" do

      it "true" do
        appointment1.update(blocked_at: nil)
        expect(appointment1.serviceable?).to eq(true)
      end

      it "false" do
        appointment1.update(blocked_at: Time.current)
        expect(appointment1.serviceable?).to eq(false)
      end

    end

    context "authorized_by_resident" do

      it "true" do
        appointment1.update(authorized_by_resident: true)
        expect(appointment1.serviceable?).to eq(true)
      end

      it "false" do
        appointment1.update(authorized_by_resident: false)
        expect(appointment1.serviceable?).to eq(false)
      end

    end

  end

  context "#requires_notifying_customer_of_change?" do

    it "is true" do
      appointment1.update(hard_break: false, skip: false, blocked_at: nil, authorized_by_resident: true)
      customer.preference.update(auth_level: Preference::NOTIFY_UNLESS_PRIMARY_OR_BACKUPS)
      pm.update(housekeeper: hk2)
      expect(appointment1.requires_notifying_customer_of_change?).to eq(true)
    end

    context "not serviceable?" do

      it "fails" do
        appointment1.update(hard_break: true, skip: false, blocked_at: nil, authorized_by_resident: true)
        customer.preference.update(auth_level: Preference::NOTIFY_UNLESS_PRIMARY_OR_BACKUPS)
        pm.update(housekeeper: hk2)
        expect(appointment1.requires_notifying_customer_of_change?).to eq(false)
      end

    end

    context "wrong auth level" do

      it "fails" do
        appointment1.update(hard_break: false, skip: false, blocked_at: nil, authorized_by_resident: true)
        customer.preference.update(auth_level: Preference::ANY_HOUSEKEEPER)
        pm.update(housekeeper: hk2)
        expect(appointment1.requires_notifying_customer_of_change?).to eq(false)
      end

    end

    context "matched with primary or backup" do

      it "fails" do
        appointment1.update(hard_break: false, skip: false, blocked_at: nil, authorized_by_resident: true)
        customer.preference.update(auth_level: Preference::NOTIFY_UNLESS_PRIMARY_OR_BACKUPS)
        expect(appointment1.requires_notifying_customer_of_change?).to eq(false)
      end

    end

  end

  context "#not_automatically_authorized?" do

    it "primary only, primary matched HK" do
      appointment1.customer.preference.update(auth_level: Preference::PRIMARY_ONLY)
      expect(appointment1.not_automatically_authorized?).to eq(false)
    end

    it "primary only, matched HK" do
      appointment1.customer.preference.update(auth_level: Preference::PRIMARY_ONLY)
      PrimaryMatch.create(
        customer: customer,
        housekeeper: hk2,
        only_use_as_backup: true,
        confirmed_by_fairy: true,
        start_at: Time.current
      )
      appointment1.housekeeper_id = hk2.id
      appointment1.save(validate: false)
      expect(appointment1.not_automatically_authorized?).to eq(true)
    end

    it "primary and backups only, matched HK" do
      appointment1.customer.preference.update(auth_level: Preference::PRIMARY_OR_BACKUPS_ONLY)
      expect(appointment1.not_automatically_authorized?).to eq(false)
    end

    it "primary and backups only, unmatched HK" do
      appointment1.customer.preference.update(auth_level: Preference::PRIMARY_OR_BACKUPS_ONLY)
      appointment1.housekeeper_id = hk2.id
      appointment1.save(validate: false)
      expect(appointment1.not_automatically_authorized?).to eq(true)
    end

    it "primary and backups only with notification" do
      appointment1.customer.preference.update(auth_level: Preference::NOTIFY_UNLESS_PRIMARY_OR_BACKUPS)
      appointment1.housekeeper_id = hk2.id
      appointment1.save(validate: false)
      expect(appointment1.not_automatically_authorized?).to eq(false)
    end

    it "any housekeeper" do
      appointment1.customer.preference.update(auth_level: Preference::ANY_HOUSEKEEPER)
      appointment1.housekeeper_id = hk2.id
      appointment1.save(validate: false)
      expect(appointment1.not_automatically_authorized?).to eq(false)
    end

  end

  context "#set_authorization" do

    it "is primary matched" do
      appointment1.set_authorization
      expect(appointment1.authorized_by_resident).to eq(true)
      expect(appointment1.authorization_category.to_sym).to eq(Appointment::PRIMARY_MATCH)
    end

    it "is not automatically authorized" do
      appointment1.customer.preference.update(auth_level: Preference::PRIMARY_ONLY)
      appointment1.update(housekeeper: hk2)
      appointment1.set_authorization
      expect(appointment1.authorized_by_resident).to eq(false)
      expect(appointment1.authorization_category.to_sym).to eq(Appointment::ONE_OFF)
    end

    it "is automatically one-off authorized" do
      appointment1.customer.preference.update(auth_level: Preference::NOTIFY_UNLESS_PRIMARY_OR_BACKUPS)
      appointment1.update(housekeeper: hk2)
      appointment1.set_authorization
      expect(appointment1.authorized_by_resident).to eq(true)
      expect(appointment1.authorization_category.to_sym).to eq(Appointment::ONE_OFF)
    end

  end

end