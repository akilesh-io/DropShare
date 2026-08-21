require "test_helper"

class KoppuraiTest < ActiveSupport::TestCase
  test "a new folder gets a share key that its share URL can carry" do
    koppurai = create_koppurai

    assert_match %r{\A[A-Za-z0-9_-]{4,14}\z}, koppurai.share_key,
      "the share key has to satisfy the constraint on the /:share_key route"
  end

  test "every folder gets its own share key" do
    keys = 5.times.map { create_koppurai.share_key }

    assert_equal keys.uniq, keys
  end

  test "an existing folder keeps the share key it was given" do
    koppurai = create_koppurai
    share_key = koppurai.share_key

    koppurai.update! title: "Holiday photos"

    assert_equal share_key, koppurai.reload.share_key
  end

  test "a folder has to say when it expires" do
    koppurai = Koppurai.new session_id: SecureRandom.uuid

    assert_not koppurai.valid?
    assert_includes koppurai.errors[:expires_at], "can't be blank"
  end

  test "a new folder starts with nothing downloaded and nothing stored" do
    koppurai = create_koppurai

    assert_equal 0, koppurai.downloads_count
    assert_equal 0, koppurai.total_size
  end

  test "a folder is expired once its expiry has passed" do
    assert create_koppurai(expires_at: 1.second.ago).expired?
    assert_not create_koppurai(expires_at: 1.hour.from_now).expired?
  end

  test "a folder holds the files dropped into it" do
    koppurai = create_koppurai
    koppu = create_koppu koppurai: koppurai

    assert_equal [ koppu ], koppurai.koppus.to_a
  end

  test "total size follows the files in the folder" do
    koppurai = create_koppurai

    create_koppu koppurai: koppurai, content: "hello"
    assert_equal 5, koppurai.reload.total_size

    koppu = create_koppu koppurai: koppurai, content: " world", filename: "second.txt"
    assert_equal 11, koppurai.reload.total_size

    koppu.destroy
    assert_equal 5, koppurai.reload.total_size
  end

  test "deleting a folder deletes the files inside it" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai
    create_koppu koppurai: koppurai, filename: "second.txt"

    assert_difference -> { Koppu.count }, -2 do
      koppurai.destroy
    end
  end
end
