Sidetiq.configure do |config|
  # Clock resolution in seconds (default: 1).
  config.resolution = 60

  # Clock locking key expiration in ms (default: 1000).
  config.lock_expire = 100

  # When `true` uses UTC instead of local times (default: false).
  config.utc = false

  # Scheduling handler pool size (default: number of CPUs as
  # determined by Celluloid).
  config.handler_pool_size = 5

  # History stored for each worker (default: 50).
  config.worker_history = 50
end

Sidetiq::Schedulable::ClassMethods.class_eval do
  def schedule_time_zone(time_zone_name)
    zone = ActiveSupport::TimeZone[time_zone_name]
    schedule.start_time = zone.local(2010, 1, 1)
  end
end

Sidetiq::Schedule.class_eval do
  def time_zone
    start_time.time_zone
  end
end

# Require all existing scheduled jobs
# Dir[Rails.root.join "app/workers/*.rb"].each { |f| require f }