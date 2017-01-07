class AvatarUploader < CarrierWave::Uploader::Base
  include Cloudinary::CarrierWave

  version :thumb do
    eager
    resize_to_fill(75, 75)
  end

  version :medium do
    eager
    resize_to_fill(200, 200)
  end

  def default_url(*args)
    "https://res.cloudinary.com/dajizl8az/image/upload/v1478084221/no-user-image.png"
  end

  def public_id
    "#{model.id}_#{(model.first_name || '').parameterize}"
  end

  def serializable_hash
    model[:avatar]
  end

  def as_json
    serializable_hash
  end

  def to_json
    serializable_hash
  end
end