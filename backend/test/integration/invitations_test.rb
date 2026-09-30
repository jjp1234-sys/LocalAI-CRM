require "test_helper"

class InvitationsTest < ActionDispatch::IntegrationTest
  def invite(email, as: :carol, role: nil)
    params = { invitation: { email_address: email, role: role }.compact }
    post biz_path(:acme, "invitations"), headers: auth_headers(as), as: :json, params: params
  end

  def new_user(name)
    User.create!(name: name.capitalize, email_address: "#{name}@example.com", password: PASSWORD)
    post "/api/v1/session", params: { email_address: "#{name}@example.com", password: PASSWORD }, as: :json
    { "Authorization" => "Bearer #{data["token"]}" }
  end

  test "an admin invites by email; the answer is the same whether or not the account exists" do
    invite("  Nobody@Example.com ")
    assert_response :accepted
    unknown = data.except("id", "email_address", "expires_at", "created_at")

    invite("mallory@example.com")
    assert_response :accepted
    assert_equal unknown, data.except("id", "email_address", "expires_at", "created_at")
    assert_equal %w[created_at email_address expires_at id role], data.keys.sort
    assert_equal "nobody@example.com", Invitation.order(:created_at).first.email_address
  end

  test "inviting doesn't make anyone a member" do
    invite("mallory@example.com")
    assert_not Membership.exists?(business_id: businesses(:acme).id, user_id: users(:mallory).id)
    get biz_path(:acme, "leads"), headers: auth_headers(:mallory)
    assert_response :not_found
  end

  test "the invitee sees it and accepting makes them a member with the invited role" do
    invite("mallory@example.com", role: "admin")

    get "/api/v1/invitations", headers: auth_headers(:mallory)
    assert_response :ok
    assert_equal [ "Acme AV" ], data.map { |i| i.dig("business", "name") }

    post "/api/v1/invitations/#{data.first["id"]}/accept", headers: auth_headers(:mallory)
    assert_response :ok
    assert_equal "admin", Membership.find_by!(business: businesses(:acme), user: users(:mallory)).role
    assert_equal "owner", memberships(:mallory_globex).reload.role, "their other business is untouched"

    get "/api/v1/invitations", headers: auth_headers(:mallory)
    assert_empty data
  end

  test "someone who signs up later can accept an invitation sent before" do
    invite("dave@example.com")
    dave = new_user("dave")
    get "/api/v1/invitations", headers: dave
    post "/api/v1/invitations/#{data.first["id"]}/accept", headers: dave
    assert_response :ok
  end

  test "only the invited email can see, accept or decline it" do
    invite("mallory@example.com")
    id = Invitation.last.id

    get "/api/v1/invitations", headers: auth_headers(:bob)
    assert_empty data
    post "/api/v1/invitations/#{id}/accept", headers: auth_headers(:bob)
    assert_response :not_found
    post "/api/v1/invitations/#{id}/decline", headers: auth_headers(:bob)
    assert_response :not_found
  end

  test "declining closes it without joining" do
    invite("mallory@example.com")
    post "/api/v1/invitations/#{Invitation.last.id}/decline", headers: auth_headers(:mallory)
    assert_response :no_content
    post "/api/v1/invitations/#{Invitation.last.id}/accept", headers: auth_headers(:mallory)
    assert_response :not_found
    assert_not Membership.exists?(business_id: businesses(:acme).id, user_id: users(:mallory).id)
  end

  test "expired and revoked invitations can't be accepted" do
    invite("mallory@example.com")
    invitation = Invitation.last
    invitation.update_columns(expires_at: 1.minute.ago)
    post "/api/v1/invitations/#{invitation.id}/accept", headers: auth_headers(:mallory)
    assert_response :not_found

    invite("mallory@example.com")
    delete biz_path(:acme, "invitations", Invitation.last.id), headers: auth_headers(:carol)
    assert_response :no_content
    post "/api/v1/invitations/#{Invitation.last.id}/accept", headers: auth_headers(:mallory)
    assert_response :not_found
  end

  test "re-inviting replaces the open invitation" do
    invite("mallory@example.com")
    invite("mallory@example.com", role: "admin")
    assert_response :accepted
    assert_equal [ "admin" ], Invitation.pending.where(email_address: "mallory@example.com").pluck(:role)
  end

  test "accepting when already a member just closes the invitation" do
    invite("bob@example.com", role: "admin")
    post "/api/v1/invitations/#{Invitation.last.id}/accept", headers: auth_headers(:bob)
    assert_response :ok
    assert_equal "agent", memberships(:bob_acme).reload.role
  end

  test "role rules: agents can't invite, admins can't invite owners, owners can" do
    invite("x@example.com", as: :bob)
    assert_response :forbidden
    invite("x@example.com", as: :carol, role: "owner")
    assert_response :forbidden
    invite("x@example.com", as: :alice, role: "owner")
    assert_response :accepted
  end

  test "bad input is a 422" do
    invite("not an email")
    assert_response :unprocessable_content
    invite("x@example.com", role: "superuser")
    assert_response :unprocessable_content
  end

  test "admins list pending invitations for their business only" do
    invite("x@example.com")
    get biz_path(:acme, "invitations"), headers: auth_headers(:carol)
    assert_equal [ "x@example.com" ], data.map { |i| i["email_address"] }
    get biz_path(:globex, "invitations"), headers: auth_headers(:mallory)
    assert_empty data
    get biz_path(:acme, "invitations"), headers: auth_headers(:bob)
    assert_response :forbidden
  end

  test "another business can't revoke this business's invitation" do
    invite("x@example.com")
    delete biz_path(:globex, "invitations", Invitation.last.id), headers: auth_headers(:mallory)
    assert_response :not_found
    assert Invitation.last.revoked_at.nil?
  end
end
