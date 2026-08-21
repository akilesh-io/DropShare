require "test_helper"

# Shared files are meant to go away on their own. The job is what makes that happen -- it
# runs every hour in production, from config/recurring.yml.
class CleanupExpiredKoppuraisJobTest < ActiveJob::TestCase
  test "a folder past its expiry is swept up" do
    koppurai = create_koppurai expires_at: 1.minute.ago

    CleanupExpiredKoppuraisJob.perform_now

    assert_not Koppurai.exists?(koppurai.id)
  end

  test "a folder that still has time is left alone" do
    koppurai = create_koppurai expires_at: 1.hour.from_now

    CleanupExpiredKoppuraisJob.perform_now

    assert Koppurai.exists?(koppurai.id)
  end

  test "the files in a swept up folder go with it" do
    koppurai = create_koppurai expires_at: 1.minute.ago
    create_koppu koppurai: koppurai
    create_koppu koppurai: koppurai, filename: "second.txt"

    assert_difference -> { Koppu.count }, -2 do
      CleanupExpiredKoppuraisJob.perform_now
    end
  end

  test "sweeping a folder up takes its files off the running totals" do
    koppurai = create_koppurai expires_at: 1.minute.ago
    create_koppu koppurai: koppurai, content: "hello"
    before = Stat.instance

    CleanupExpiredKoppuraisJob.perform_now

    stats = Stat.instance
    assert_equal before.current_uploads - 1, stats.current_uploads
    assert_equal before.current_size - 5, stats.current_size
    assert_equal before.lifetime_uploads, stats.lifetime_uploads
  end

  test "the attachments of a swept up folder are sent off to be purged" do
    koppurai = create_koppurai expires_at: 1.minute.ago
    create_koppu koppurai: koppurai

    assert_enqueued_with job: ActiveStorage::PurgeJob do
      CleanupExpiredKoppuraisJob.perform_now
    end
  end

  test "a run with nothing to sweep up leaves everything where it is" do
    create_koppurai expires_at: 1.hour.from_now
    create_koppu

    assert_no_difference [ -> { Koppurai.count }, -> { Koppu.count } ] do
      CleanupExpiredKoppuraisJob.perform_now
    end
  end

  test "the job goes on the default queue" do
    assert_enqueued_with job: CleanupExpiredKoppuraisJob, queue: "default" do
      CleanupExpiredKoppuraisJob.perform_later
    end
  end
end
