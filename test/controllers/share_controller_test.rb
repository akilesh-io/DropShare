require "test_helper"

# The receiving side: what someone who was sent a link gets. Nothing here is owned by the
# visitor, so a link is the whole of the authorization -- an unknown one is a 404, and an
# expired one is a 410 whether it is aimed at a folder, a file, or a preview.
class ShareControllerTest < ActionDispatch::IntegrationTest
  UNKNOWN_KEY = "notarealkey"

  test "opening a shared folder" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai, filename: "notes.txt"

    get share_path(koppurai.share_key)

    assert_response :success
    assert_select "[data-folder-id=?]", koppurai.id.to_s
    assert_match "notes.txt", response.body
  end

  test "a visitor to a shared folder is offered the files but not the delete buttons" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai

    get share_path(koppurai.share_key)

    assert_select "a.download-all-btn[href=?]", download_folder_path(share_key: koppurai.share_key)
    assert_select "form[action=?]", destroy_koppurai_drop_path(koppurai), count: 0
  end

  test "a folder nobody shared is not found" do
    get share_path(UNKNOWN_KEY)

    assert_response :not_found
  end

  test "a folder whose time is up is gone" do
    koppurai = create_koppurai expires_at: 1.minute.ago

    get share_path(koppurai.share_key)

    assert_response :gone
  end

  test "downloading a shared file" do
    koppu = create_koppu filename: "notes.txt"

    get download_koppu_path(share_key: koppu.share_key)

    assert_response :redirect
    assert_match "notes.txt", response.location
    assert_match "disposition=attachment", response.location
  end

  test "downloading a file is counted for the file, the folder, and the server" do
    koppu = create_koppu
    downloads = Stat.instance.total_downloads

    get download_koppu_path(share_key: koppu.share_key)

    assert_equal 1, koppu.reload.downloads_count
    assert_equal 1, koppu.koppurai.reload.downloads_count
    assert_equal downloads + 1, Stat.instance.total_downloads
  end

  test "a file nobody shared is not found" do
    get download_koppu_path(share_key: UNKNOWN_KEY)

    assert_response :not_found
  end

  test "a file whose folder has expired is gone" do
    koppu = create_koppu koppurai: create_koppurai(expires_at: 1.minute.ago)

    get download_koppu_path(share_key: koppu.share_key)

    assert_response :gone
    assert_equal 0, koppu.reload.downloads_count, "nothing was downloaded, so nothing is counted"
  end

  test "previewing a text file" do
    koppu = create_koppu filename: "notes.txt", content: "hello world"

    get text_preview_path(share_key: koppu.share_key)

    assert_response :success
    assert_equal "hello world", response.body
    assert_equal "text/plain", response.media_type
    assert_nil response.headers["X-Preview-Truncated"]
  end

  test "previewing only the head of a long text file" do
    koppu = create_koppu filename: "big.log", content: "x" * (ShareController::TEXT_PREVIEW_BYTES + 1.kilobyte)

    get text_preview_path(share_key: koppu.share_key)

    assert_response :success
    assert_equal ShareController::TEXT_PREVIEW_BYTES, response.body.bytesize
    assert_equal "1", response.headers["X-Preview-Truncated"]
  end

  test "previewing a file whose bytes are not text" do
    koppu = create_koppu filename: "photo.png", content: "\x89PNG\r\n\x1a\n".b, content_type: "image/png"

    get text_preview_path(share_key: koppu.share_key)

    assert_response :unsupported_media_type
  end

  test "a preview of a file nobody shared is not found" do
    get text_preview_path(share_key: UNKNOWN_KEY)

    assert_response :not_found
  end

  test "a preview of a file whose folder has expired is gone" do
    koppu = create_koppu koppurai: create_koppurai(expires_at: 1.minute.ago)

    get text_preview_path(share_key: koppu.share_key)

    assert_response :gone
  end

  test "downloading a whole folder as a zip" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai, filename: "notes.txt", content: "hello world"
    create_koppu koppurai: koppurai, filename: "second.txt", content: "goodbye"

    get download_folder_path(share_key: koppurai.share_key)

    assert_response :success
    assert_equal({ "notes.txt" => "hello world", "second.txt" => "goodbye" }, zip_entries)
  end

  test "the zip is named after the folder" do
    koppurai = create_koppurai title: "Holiday photos!"
    create_koppu koppurai: koppurai

    get download_folder_path(share_key: koppurai.share_key)

    assert_match %r{filename="Holiday_photos_\.zip"}, response.headers["Content-Disposition"]
  end

  test "a folder with no title falls back to the name of the app" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai

    get download_folder_path(share_key: koppurai.share_key)

    assert_match %r{filename="DropShare\.zip"}, response.headers["Content-Disposition"]
  end

  test "two files of the same name both survive the zip" do
    koppurai = create_koppurai
    3.times { create_koppu koppurai: koppurai, filename: "notes.txt", content: "hello world" }

    get download_folder_path(share_key: koppurai.share_key)

    assert_equal [ "notes.txt", "notes (1).txt", "notes (2).txt" ], zip_entries.keys
  end

  test "a filename that tries to climb out of the zip stays inside it" do
    koppurai = create_koppurai
    koppu = create_koppu koppurai: koppurai, content: "root"
    # Written past the setter, since Active Storage would sanitize it on the way in.
    koppu.koppu.blob.update_column :filename, "../../etc/passwd"

    get download_folder_path(share_key: koppurai.share_key)

    name = zip_entries.keys.sole
    assert_no_match %r{[/\\]}, name, "an entry has to unpack inside the archive, not above it"
    assert_equal "..-..-etc-passwd", name, "Active Storage turns the separators into dashes"
  end

  test "a filename that is nothing but dots still gets an entry of its own" do
    koppurai = create_koppurai
    koppu = create_koppu koppurai: koppurai, content: "root"
    koppu.koppu.blob.update_column :filename, ".."

    get download_folder_path(share_key: koppurai.share_key)

    assert_equal [ "file" ], zip_entries.keys
  end

  test "downloading a folder is counted for every file in it" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai, filename: "notes.txt"
    create_koppu koppurai: koppurai, filename: "second.txt"
    downloads = Stat.instance.total_downloads

    get download_folder_path(share_key: koppurai.share_key)

    assert_equal [ 1, 1 ], koppurai.koppus.reload.map(&:downloads_count)
    assert_equal 1, koppurai.reload.downloads_count
    assert_equal downloads + 2, Stat.instance.total_downloads
  end

  test "an empty folder has nothing to zip up" do
    koppurai = create_koppurai

    get download_folder_path(share_key: koppurai.share_key)

    assert_response :not_found
  end

  test "a folder nobody shared has no zip either" do
    get download_folder_path(share_key: UNKNOWN_KEY)

    assert_response :not_found
  end

  test "an expired folder has no zip either" do
    koppurai = create_koppurai expires_at: 1.minute.ago
    create_koppu koppurai: koppurai

    get download_folder_path(share_key: koppurai.share_key)

    assert_response :gone
  end

  private
    # Entry name => contents, in the order the archive holds them.
    def zip_entries
      Zip::File.open_buffer(StringIO.new(response.body)) do |zip|
        return zip.each_with_object({}) { |entry, entries| entries[entry.name] = entry.get_input_stream.read }
      end
    end
end
