require "test_helper"

class StatTest < ActiveSupport::TestCase
  test "there is only ever one row of stats" do
    assert_difference -> { Stat.count }, 1 do
      3.times { Stat.instance }
    end
  end

  test "the first look at the stats starts them from zero" do
    Stat.delete_all
    stats = Stat.instance

    assert_equal 0, stats.current_uploads
    assert_equal 0, stats.current_size
    assert_equal 0, stats.total_downloads
    assert_equal 0, stats.lifetime_uploads
    assert_equal 0, stats.lifetime_size
  end

  test "an upload is added to both the running and the lifetime totals" do
    Stat.delete_all

    Stat.add_upload byte_size: 1024

    stats = Stat.instance
    assert_equal 1, stats.current_uploads
    assert_equal 1024, stats.current_size
    assert_equal 1, stats.lifetime_uploads
    assert_equal 1024, stats.lifetime_size
  end

  test "removing an upload only takes it off the running totals" do
    Stat.delete_all
    Stat.add_upload byte_size: 1024

    Stat.remove_upload byte_size: 1024

    stats = Stat.instance
    assert_equal 0, stats.current_uploads
    assert_equal 0, stats.current_size
    assert_equal 1, stats.lifetime_uploads, "what has been uploaded stays uploaded"
    assert_equal 1024, stats.lifetime_size
  end

  test "several uploads can be counted at once" do
    Stat.delete_all

    Stat.add_upload byte_size: 300, count: 3
    Stat.remove_upload byte_size: 100, count: 1

    stats = Stat.instance
    assert_equal 2, stats.current_uploads
    assert_equal 200, stats.current_size
    assert_equal 3, stats.lifetime_uploads
    assert_equal 300, stats.lifetime_size
  end

  test "the carbon estimate comes from everything ever transferred" do
    stats = Stat.new lifetime_size: 10.gigabytes

    # 10 GB * 0.06 kWh/GB * 442 g/kWh = 265.2 g
    assert_in_delta 0.27, stats.estimated_co2_kg, 0.005
  end

  test "an empty server has emitted nothing" do
    assert_equal 0.0, Stat.new(lifetime_size: 0).estimated_co2_kg
  end
end
