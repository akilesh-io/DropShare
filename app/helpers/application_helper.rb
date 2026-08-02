module ApplicationHelper
  def cached_preview_url(representation)
    rails_blob_representation_proxy_path(
      signed_blob_id: representation.blob.signed_id,
      variation_key: representation.variation.key,
      filename: representation.blob.filename
    )
  end
end
