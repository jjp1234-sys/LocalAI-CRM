require "test_helper"

class MembershipsTest < ActionDispatch::IntegrationTest
  def membership_path(fixture, business = :acme)
    biz_path(business, "memberships", memberships(fixture).id)
  end

  test "any member can list the team, with no private fields" do
    get biz_path(:acme, "memberships"), headers: auth_headers(:bob)
    assert_response :ok
    assert_equal %w[admin agent owner], data.map { |m| m["role"] }.sort
    assert_equal %w[alice@example.com bob@example.com carol@example.com], data.map { |m| m.dig("user", "email_address") }.sort
    assert_equal %w[email_address id name], data.first["user"].keys.sort
    assert_equal 3, json.dig("meta", "total")
  end

  test "another business's team is 404" do
    get biz_path(:acme, "memberships"), headers: auth_headers(:mallory)
    assert_response :not_found
  end

  test "members can't be added directly; new people are invited" do
    post biz_path(:acme, "memberships"), headers: auth_headers(:alice), as: :json,
      params: { membership: { email_address: "mallory@example.com" } }
    assert_response :not_found
    assert_not Membership.exists?(business_id: businesses(:acme).id, user_id: users(:mallory).id)
  end

  test "an admin can change an agent's role but not make anyone an owner" do
    patch membership_path(:bob_acme), headers: auth_headers(:carol), as: :json, params: { membership: { role: "admin" } }
    assert_response :ok
    assert_equal "admin", data["role"]

    patch membership_path(:bob_acme), headers: auth_headers(:carol), as: :json, params: { membership: { role: "owner" } }
    assert_response :forbidden
    assert_equal "admin", memberships(:bob_acme).reload.role

    patch membership_path(:carol_acme), headers: auth_headers(:carol), as: :json, params: { membership: { role: "owner" } }
    assert_response :forbidden
    assert_equal "admin", memberships(:carol_acme).reload.role
  end

  test "an admin can't change or remove an owner" do
    patch membership_path(:alice_acme), headers: auth_headers(:carol), as: :json, params: { membership: { role: "agent" } }
    assert_response :forbidden
    delete membership_path(:alice_acme), headers: auth_headers(:carol)
    assert_response :forbidden
    assert_equal "owner", memberships(:alice_acme).reload.role
  end

  test "an agent can't change roles" do
    patch membership_path(:bob_acme), headers: auth_headers(:bob), as: :json, params: { membership: { role: "admin" } }
    assert_response :forbidden
    assert_equal "agent", memberships(:bob_acme).reload.role
  end

  test "an owner can promote to owner, and then step down" do
    patch membership_path(:carol_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "owner" } }
    assert_response :ok
    assert_equal "owner", data["role"]

    patch membership_path(:alice_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "admin" } }
    assert_response :ok
    assert_equal "admin", memberships(:alice_acme).reload.role
  end

  test "an owner can demote and remove another owner" do
    patch membership_path(:carol_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "owner" } }
    assert_response :ok
    patch membership_path(:carol_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "agent" } }
    assert_response :ok
    patch membership_path(:carol_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "owner" } }
    delete membership_path(:carol_acme), headers: auth_headers(:alice)
    assert_response :no_content
    assert_not Membership.exists?(memberships(:carol_acme).id)
  end

  test "the last owner can't be demoted" do
    patch membership_path(:alice_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "admin" } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "role").present?
    assert_equal "owner", memberships(:alice_acme).reload.role
  end

  test "the last owner can't be removed" do
    assert_no_difference -> { Membership.count } do
      delete membership_path(:alice_acme), headers: auth_headers(:alice)
    end
    assert_response :unprocessable_content
  end

  test "an admin removes an agent, who then loses access" do
    delete membership_path(:bob_acme), headers: auth_headers(:carol)
    assert_response :no_content
    get biz_path(:acme, "leads"), headers: auth_headers(:bob)
    assert_response :not_found
  end

  test "an admin can remove themselves" do
    delete membership_path(:carol_acme), headers: auth_headers(:carol)
    assert_response :no_content
    get biz_path(:acme), headers: auth_headers(:carol)
    assert_response :not_found
  end

  test "an owner with a co-owner can leave" do
    patch membership_path(:carol_acme), headers: auth_headers(:alice), as: :json, params: { membership: { role: "owner" } }
    delete membership_path(:alice_acme), headers: auth_headers(:alice)
    assert_response :no_content
  end

  test "an agent can leave, but can't remove anyone else" do
    delete membership_path(:carol_acme), headers: auth_headers(:bob)
    assert_response :forbidden
    assert Membership.exists?(memberships(:carol_acme).id)

    delete membership_path(:bob_acme), headers: auth_headers(:bob)
    assert_response :no_content
    get biz_path(:acme, "leads"), headers: auth_headers(:bob)
    assert_response :not_found
  end

  test "another business's memberships are 404" do
    patch membership_path(:mallory_globex, :acme), headers: auth_headers(:alice), as: :json,
      params: { membership: { role: "agent" } }
    assert_response :not_found
    delete membership_path(:mallory_globex, :acme), headers: auth_headers(:alice)
    assert_response :not_found

    delete membership_path(:bob_acme, :globex), headers: auth_headers(:mallory)
    assert_response :not_found
    assert Membership.exists?(memberships(:bob_acme).id)
  end
end
