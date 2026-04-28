require "test_helper"

class ShareControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get share_index_url
    assert_response :success
  end
end
