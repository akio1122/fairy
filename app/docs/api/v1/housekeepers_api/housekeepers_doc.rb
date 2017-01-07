module Api::V1::HousekeepersApi::HousekeepersDoc
  extend BaseDoc

  namespace('api/v1/housekeepers_api', { name: 'housekeepers_api' })

  resource :housekeepers

  resource_description do
    short 'API for housekeeper customers management'
  end

  doc_for :ping do
    api :POST, '/hk/housekeepers/:id/ping', 'Track connectivity state'
    auth_with :password

    param :id, Integer, required: true
    param :lat, Float
    param :lng, Float
    param :connectivity_type, String, required: true
    param :battery_level, Float, required: true

    description <<-EOS
      It returns <tt> No content status code</tt>.
    EOS
  end
end