module Api
  extend ActiveSupport::Concern

  included do
    def called_from_api?
      $request.present? && $request != "Email" && $request.env["REQUEST_PATH"].present? && $request.env["REQUEST_PATH"].split("/")[1] == "api"
    end
  end
end