require "test_helper"

class PaymentControllerTest < ActionDispatch::IntegrationTest
  test "should get payment" do
    get payment_payment_url
    assert_response :success
  end
end
