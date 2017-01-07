Apipie.configure do |config|
  config.app_name = "Fairy API"
  config.doc_base_url = "/documentation"
  config.api_base_url = "/api/v1"

  config.api_controllers_matcher = "#{Rails.root}/app/controllers/api/**/*.rb"
  config.validate                 = false
  config.show_all_examples        = true
  config.reload_controllers       = Rails.env.development?
  config.authenticate             = Proc.new do
    authenticate_user!
  end

  config.app_info                 = <<-EOS
    <b>API authentication</b>
    All Reuqests must be signed with an <tt>token</tt> header, unless marked [PUBLIC].

    This is a token provided during authentication and used to validate as well as identify users.

    E.g.,
      "token" => "xxxxxxxxxxxx"

    Any incorrectly authorized requests will return <tt>Token: Access denied</tt> with status <tt>401</tt>.

    All api endpoints marked [PUBLIC] must be signed with HTTP BASIC authentication.
  EOS
end