module ApplicationHelper
  LIGHTBOX_MAX_DIMENSION = 2000

  def cached_preview_url(representation)
    rails_blob_representation_proxy_path(
      signed_blob_id: representation.blob.signed_id,
      variation_key: representation.variation.key,
      filename: representation.blob.filename
    )
  end

  def lightbox_url(attachment)
    cached_preview_url(attachment.representation(resize_to_limit: [LIGHTBOX_MAX_DIMENSION, LIGHTBOX_MAX_DIMENSION]))
  end
end
