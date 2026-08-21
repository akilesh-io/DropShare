require "test_helper"

# The dropping side of the app: the page someone lands on, the folders they make there,
# and the files they put in and take out again. Whoever holds the session that made a
# folder owns it -- there are no accounts -- so most of what is checked here is that a
# second visitor can look but not touch.
class DropControllerTest < ActionDispatch::IntegrationTest
  test "the front page is there to drop onto" do
    get root_path

    assert_response :success
    assert_select ".drop-area"
  end

  test "a visitor with nothing shared yet is shown what the server has carried" do
    get root_path

    assert_response :success
    assert_select ".stats"
  end

  test "a visitor is given a session to hold their folders under" do
    get root_path

    assert session[:user_id].present?
  end

  test "the session survives from one request to the next" do
    get root_path
    user_id = session[:user_id]

    get root_path

    assert_equal user_id, session[:user_id]
  end

  test "the front page lists the folders this session made" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])

    get root_path

    assert_response :success
    assert_select "[data-folder-id=?]", koppurai.id.to_s
  end

  test "the front page keeps someone else's folders to themselves" do
    stranger = create_koppurai

    get root_path

    assert_response :success
    assert_select "[data-folder-id=?]", stranger.id.to_s, count: 0
    assert_no_match stranger.share_key, response.body
  end

  test "making a folder" do
    assert_difference -> { Koppurai.count }, 1 do
      post new_drop_path
    end

    assert_response :success

    koppurai = Koppurai.last
    assert_equal session[:user_id], koppurai.session_id
    assert_in_delta Rails.configuration.FILE_EXPIRY_DAYS.days.from_now, koppurai.expires_at, 5.seconds
    assert_select "[data-folder-id=?]", koppurai.id.to_s
  end

  test "putting a file in a folder" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])
    blob = create_blob filename: "notes.txt", content: "hello world"

    assert_difference -> { koppurai.koppus.count }, 1 do
      post drop_index_path, as: :json, params: { blob_signed_id: blob.signed_id, koppurai_id: koppurai.id }
    end

    assert_response :success

    koppu = koppurai.koppus.last
    assert_equal "hello world", koppu.koppu.download
    assert_equal "notes.txt", koppu.koppu.filename.to_s
    assert_equal 11, koppu.byte_size
    assert_equal "text/plain", koppu.content_type
    assert_equal blob.checksum, koppu.checksum
    assert_select "[data-file-id=?]", koppu.id.to_s
  end

  test "refusing a file that came without a blob" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])

    assert_no_difference -> { Koppu.count } do
      post drop_index_path, as: :json, params: { koppurai_id: koppurai.id }
    end

    assert_response :bad_request
    assert_equal "No file", response.parsed_body["error"]
  end

  test "refusing a file for a folder that isn't yours" do
    get root_path
    stranger = create_koppurai
    blob = create_blob

    assert_no_difference -> { Koppu.count } do
      post drop_index_path, as: :json, params: { blob_signed_id: blob.signed_id, koppurai_id: stranger.id }
    end

    assert_response :not_found
    assert_equal "Upload failed", response.parsed_body["error"]
  end

  test "refusing a file for a folder that doesn't exist" do
    get root_path
    blob = create_blob

    post drop_index_path, as: :json, params: { blob_signed_id: blob.signed_id, koppurai_id: 0 }

    assert_response :not_found
  end

  test "refusing a blob whose signature doesn't hold up" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])

    assert_no_difference -> { Koppu.count } do
      post drop_index_path, as: :json, params: { blob_signed_id: "not-a-signed-id", koppurai_id: koppurai.id }
    end

    assert_response :not_found
  end

  test "refusing a file larger than a folder will hold" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])
    blob = create_blob
    blob.update! byte_size: Koppu::MAX_BYTE_SIZE + 1

    assert_no_difference -> { Koppu.count } do
      post drop_index_path, as: :json, params: { blob_signed_id: blob.signed_id, koppurai_id: koppurai.id }
    end

    assert_response :unprocessable_content
    assert_match "must be less than", response.parsed_body["error"]
  end

  test "refusing a file once the folder is full" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])

    with_constant Koppu, :MAX_PER_KOPPURAI, 1 do
      create_koppu koppurai: koppurai
      blob = create_blob filename: "second.txt"

      assert_no_difference -> { Koppu.count } do
        post drop_index_path, as: :json, params: { blob_signed_id: blob.signed_id, koppurai_id: koppurai.id }
      end

      assert_response :unprocessable_content
      assert_equal "Folder is full (max 1 files)", response.parsed_body["error"]
    end
  end

  test "deleting a folder of your own" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])
    create_koppu koppurai: koppurai

    assert_difference [ -> { Koppurai.count }, -> { Koppu.count } ], -1 do
      delete destroy_koppurai_drop_path(koppurai)
    end

    assert_redirected_to root_path
  end

  test "refusing to delete a folder that isn't yours" do
    get root_path
    stranger = create_koppurai

    assert_no_difference -> { Koppurai.count } do
      delete destroy_koppurai_drop_path(stranger)
    end

    assert_response :forbidden
  end

  test "deleting a file of your own" do
    post new_drop_path
    koppurai = Koppurai.find_by!(session_id: session[:user_id])
    koppu = create_koppu koppurai: koppurai

    assert_difference -> { Koppu.count }, -1 do
      delete destroy_koppu_drop_path(koppu)
    end

    assert_redirected_to root_path
    assert_equal 0, koppurai.reload.total_size
  end

  test "refusing to delete a file that isn't yours" do
    get root_path
    koppu = create_koppu

    assert_no_difference -> { Koppu.count } do
      delete destroy_koppu_drop_path(koppu)
    end

    assert_response :forbidden
  end
end
