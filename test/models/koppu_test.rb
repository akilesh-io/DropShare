require "test_helper"

class KoppuTest < ActiveSupport::TestCase
  test "a new file gets a share key that its download URL can carry" do
    assert_match %r{\A[A-Za-z0-9_-]{4,14}\z}, create_koppu.share_key,
      "the share key has to satisfy the constraint on the /f/:share_key route"
  end

  test "every file gets its own share key" do
    koppurai = create_koppurai
    keys = 5.times.map { |i| create_koppu(koppurai: koppurai, filename: "file-#{i}.txt").share_key }

    assert_equal keys.uniq, keys
  end

  test "a new file starts with nothing downloaded" do
    assert_equal 0, create_koppu.downloads_count
  end

  test "a file row without an attachment is no file at all" do
    koppu = create_koppurai.koppus.new byte_size: 11, content_type: "text/plain"

    assert_not koppu.valid?
    assert_includes koppu.errors[:koppu], "can't be blank"
  end

  test "a file has to belong to a folder" do
    koppu = Koppu.new byte_size: 11
    koppu.koppu.attach create_blob

    assert_not koppu.valid?
    assert_includes koppu.errors[:koppurai], "must exist"
  end

  test "a file bigger than the limit is refused" do
    koppurai = create_koppurai
    koppu = koppurai.koppus.new byte_size: Koppu::MAX_BYTE_SIZE, content_type: "text/plain"
    koppu.koppu.attach create_blob

    assert_not koppu.valid?
    assert_includes koppu.errors[:byte_size], "must be less than #{Koppu::MAX_BYTE_SIZE}"
  end

  test "a file is refused once the folder is full" do
    koppurai = create_koppurai

    with_constant Koppu, :MAX_PER_KOPPURAI, 2 do
      create_koppu koppurai: koppurai, filename: "first.txt"
      create_koppu koppurai: koppurai, filename: "second.txt"

      koppu = koppurai.koppus.new byte_size: 11, content_type: "text/plain"
      koppu.koppu.attach create_blob

      assert_not koppu.valid?
      assert_includes koppu.errors[:base], "Folder is full (max 2 files)"
    end
  end

  test "a full folder still lets the files already in it be saved again" do
    koppurai = create_koppurai

    with_constant Koppu, :MAX_PER_KOPPURAI, 1 do
      koppu = create_koppu koppurai: koppurai

      assert koppu.update(downloads_count: 1), "capacity is only checked when a file is added"
    end
  end

  test "storing a file counts towards the running and the lifetime totals" do
    before = Stat.instance

    create_koppu content: "hello"

    stats = Stat.instance
    assert_equal before.current_uploads + 1, stats.current_uploads
    assert_equal before.current_size + 5, stats.current_size
    assert_equal before.lifetime_uploads + 1, stats.lifetime_uploads
    assert_equal before.lifetime_size + 5, stats.lifetime_size
  end

  test "deleting a file takes it off the running totals but leaves the lifetime ones" do
    koppu = create_koppu content: "hello"
    before = Stat.instance

    koppu.destroy

    stats = Stat.instance
    assert_equal before.current_uploads - 1, stats.current_uploads
    assert_equal before.current_size - 5, stats.current_size
    assert_equal before.lifetime_uploads, stats.lifetime_uploads, "a file that was here once was still uploaded"
    assert_equal before.lifetime_size, stats.lifetime_size
  end

  test "deleting a folder takes its files off the running totals" do
    koppurai = create_koppurai
    create_koppu koppurai: koppurai, content: "hello"
    create_koppu koppurai: koppurai, content: " world", filename: "second.txt"
    before = Stat.instance

    koppurai.destroy

    stats = Stat.instance
    assert_equal before.current_uploads - 2, stats.current_uploads
    assert_equal before.current_size - 11, stats.current_size
  end

  test "the attachment carries the file itself" do
    koppu = create_koppu filename: "notes.txt", content: "hello world", content_type: "text/plain"

    assert koppu.koppu.attached?
    assert_equal "hello world", koppu.koppu.download
    assert_equal "notes.txt", koppu.koppu.filename.to_s
    assert_equal 11, koppu.byte_size
    assert_equal "text/plain", koppu.content_type
  end
end
