require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  setup do
    koppu = create_koppu filename: "photo.png", content: "not really a png", content_type: "image/png"
    @attachment = koppu.koppu
  end

  test "a preview is served through the proxy, so a browser can cache it" do
    url = lightbox_url(@attachment)

    assert_match %r{\A/rails/active_storage/representations/proxy/}, url
    assert_match @attachment.blob.signed_id, url
    assert_match "photo.png", url
  end

  test "the same picture asked for twice gives the same URL" do
    assert_equal lightbox_url(@attachment), lightbox_url(@attachment),
      "a URL that changes every time is a URL that is never cached"
  end

  test "two sizes of the same picture are told apart" do
    small = cached_preview_url(@attachment.representation(resize_to_limit: [ 200, 200 ]))

    assert_not_equal small, lightbox_url(@attachment)
  end
end
