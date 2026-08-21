require "test_helper"

# What the drop page decides about a file it has never opened: whether it can be shown as
# text, and which icon stands in for it.
class DropHelperTest < ActionView::TestCase
  test "a file with a text extension can be previewed" do
    assert text_previewable?(blob("notes.txt"))
    assert text_previewable?(blob("README.md"))
    assert text_previewable?(blob("app.rb"))
    assert text_previewable?(blob("data.csv"))
    assert text_previewable?(blob("config.yml"))
  end

  test "the extension is read without regard to case" do
    assert text_previewable?(blob("NOTES.TXT"))
    assert text_previewable?(blob("Schema.SQL"))
  end

  test "a file whose name alone says it is text can be previewed" do
    assert text_previewable?(blob("Dockerfile", content_type: "application/octet-stream"))
    assert text_previewable?(blob("Makefile", content_type: "application/octet-stream"))
    assert text_previewable?(blob("LICENSE", content_type: "application/octet-stream"))
  end

  test "a dotfile is read by the name under the dot" do
    assert text_previewable?(blob(".gitignore", content_type: "application/octet-stream"))
  end

  test "a file the server calls text can be previewed whatever it is named" do
    assert text_previewable?(blob("payload.weird", content_type: "text/plain"))
    assert text_previewable?(blob("payload.weird", content_type: "application/json"))
    assert text_previewable?(blob("payload.weird", content_type: "application/x-ruby"))
  end

  test "a file that is neither named nor typed as text cannot be previewed" do
    assert_not text_previewable?(blob("photo.png", content_type: "image/png"))
    assert_not text_previewable?(blob("clip.mp4", content_type: "video/mp4"))
    assert_not text_previewable?(blob("archive.zip", content_type: "application/zip"))
    assert_not text_previewable?(blob("mystery", content_type: "application/octet-stream"))
  end

  test "each kind of file gets the icon that stands for its kind" do
    assert_equal "icons/audio.svg", attachment_icon(blob("song.mp3"))
    assert_equal "icons/code.svg", attachment_icon(blob("app.rb"))
    assert_equal "icons/document.svg", attachment_icon(blob("notes.txt"))
    assert_equal "icons/spreadsheets.svg", attachment_icon(blob("budget.xlsx"))
    assert_equal "icons/image.svg", attachment_icon(blob("photo.png"))
    assert_equal "icons/video.svg", attachment_icon(blob("clip.mp4"))
    assert_equal "icons/pdf-simple.svg", attachment_icon(blob("contract.pdf"))
    assert_equal "icons/zip.svg", attachment_icon(blob("archive.zip"))
  end

  test "the icon is chosen without regard to case" do
    assert_equal "icons/image.svg", attachment_icon(blob("PHOTO.PNG"))
  end

  test "a file with an icon of its own gets it" do
    assert_equal "icons/psd.svg", attachment_icon(blob("poster.psd"))
    assert_equal "icons/json.svg", attachment_icon(blob("data.json"))
  end

  test "a file we have no icon for gets the blank one" do
    assert_equal "icons/empty.svg", attachment_icon(blob("mystery.xyz"))
    assert_equal "icons/empty.svg", attachment_icon(blob("mystery"))
  end

  private
    def blob(filename, content_type: nil)
      ActiveStorage::Blob.new filename: filename, content_type: content_type
    end
end
