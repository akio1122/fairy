Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDISTOGO_URL'] }
  config.error_handlers << Proc.new { |ex, ctx_hash| Rollbar.error(ex, ctx_hash) }
end

Sidekiq.configure_client do |config|
  config.redis = { size: ENV['REDIS_CLIENT_SIZE'] || 6, url: ENV['REDISTOGO_URL'] }
end

Sidekiq.default_worker_options = {
    'backtrace' => true
}

Sidekiq::Web.set :session_secret, Rails.application.secrets[:secret_token]
Sidekiq::Web.set :sessions, Rails.application.config.session_options