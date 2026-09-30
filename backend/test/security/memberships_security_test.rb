require "test_helper"

class MembershipsSecurityTest < ActionDispatch::IntegrationTest
  # Originally: any business owner could add any registered user by email,
  # with no consent, and the response revealed their name and ID. Adding
  # people is now an invitation the invitee has to accept.
  test "an unrelated business can't add a user without their consent" do
    post biz_path(:globex, "memberships"), headers: auth_headers(:mallory), as: :json,
      params: { membership: { email_address: "alice@example.com", role: "agent" } }
    assert_not_equal 201, response.status

    post biz_path(:globex, "invitations"), headers: auth_headers(:mallory), as: :json,
      params: { invitation: { email_address: "alice@example.com", role: "agent" } }
    assert_response :accepted
    assert_not Membership.exists?(business_id: businesses(:globex).id, user_id: users(:alice).id)
    assert_nil data["user"], "the invitation response must not reveal the invitee's account"
  end

  test "inviting doesn't reveal which emails have accounts" do
    post biz_path(:globex, "invitations"), headers: auth_headers(:mallory), as: :json,
      params: { invitation: { email_address: "nobody-here@example.com", role: "agent" } }
    unknown = [ response.status, data.keys.sort ]

    post biz_path(:globex, "invitations"), headers: auth_headers(:mallory), as: :json,
      params: { invitation: { email_address: "bob@example.com", role: "agent" } }
    known = [ response.status, data.keys.sort ]

    assert_equal unknown, known, "the response differs for registered and unregistered emails"
  end

  # Held up.

  test "admin can't promote anyone to owner" do
    patch biz_path(:acme, "memberships", memberships(:bob_acme).id), headers: auth_headers(:carol), as: :json,
      params: { membership: { role: "owner" } }
    assert_response :forbidden
  end

  test "admin can't demote or remove an owner" do
    patch biz_path(:acme, "memberships", memberships(:alice_acme).id), headers: auth_headers(:carol), as: :json,
      params: { membership: { role: "agent" } }
    assert_response :forbidden

    delete biz_path(:acme, "memberships", memberships(:alice_acme).id), headers: auth_headers(:carol)
    assert_response :forbidden
  end

  test "admin can't self-promote to owner" do
    patch biz_path(:acme, "memberships", memberships(:carol_acme).id), headers: auth_headers(:carol), as: :json,
      params: { membership: { role: "owner" } }
    assert_response :forbidden
  end

  test "agent can't change roles" do
    patch biz_path(:acme, "memberships", memberships(:bob_acme).id), headers: auth_headers(:bob), as: :json,
      params: { membership: { role: "admin" } }
    assert_response :forbidden
  end

  test "last owner can't demote or remove themselves" do
    patch biz_path(:acme, "memberships", memberships(:alice_acme).id), headers: auth_headers(:alice), as: :json,
      params: { membership: { role: "admin" } }
    assert_response :unprocessable_content

    delete biz_path(:acme, "memberships", memberships(:alice_acme).id), headers: auth_headers(:alice)
    assert_response :unprocessable_content
  end

  test "role sent as an array is not accepted" do
    post biz_path(:acme, "memberships"), headers: auth_headers(:carol), as: :json,
      params: { membership: { email_address: "mallory@example.com", role: [ "owner" ] } }
    assert_not_equal "owner", (data["role"] if response.status == 201)
  end

  test "another business's membership can't be changed or removed" do
    id = memberships(:mallory_globex).id
    patch biz_path(:acme, "memberships", id), headers: auth_headers(:alice), as: :json,
      params: { membership: { role: "agent" } }
    assert_response :not_found

    delete biz_path(:acme, "memberships", id), headers: auth_headers(:alice)
    assert_response :not_found
    assert_equal "owner", memberships(:mallory_globex).reload.role
  end
end
