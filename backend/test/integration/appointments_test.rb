require "test_helper"

class AppointmentsTest < ActionDispatch::IntegrationTest
  def create_appointment(starts_at:, ends_at: nil, user: :bob, **attrs)
    post biz_path(:acme, "appointments"), headers: auth_headers(user), as: :json, params: {
      appointment: { lead_id: leads(:michael).id, starts_at: starts_at.iso8601, ends_at: (ends_at || starts_at + 1.hour).iso8601 }.merge(attrs)
    }
  end

  test "without from/to, lists only upcoming appointments in the business" do
    create_appointment(starts_at: 2.days.ago)
    assert_response :created
    past_id = data["id"]

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob)
    assert_response :ok
    ids = data.map { |a| a["id"] }
    assert_equal [ appointments(:sarah_consult).id ], ids
    assert_not_includes ids, past_id
    assert_not_includes ids, appointments(:globex_visit).id
  end

  test "lists appointments in a from/to window, ordered by start" do
    create_appointment(starts_at: 2.days.ago)
    past_id = data["id"]
    create_appointment(starts_at: 10.days.from_now)
    far_id = data["id"]

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob),
      params: { from: 3.days.ago.utc.iso8601, to: 3.days.from_now.utc.iso8601 }
    assert_response :ok
    assert_equal [ past_id, appointments(:sarah_consult).id ], data.map { |a| a["id"] }

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { from: 5.days.from_now.utc.iso8601 }
    assert_equal [ far_id ], data.map { |a| a["id"] }

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { to: 5.days.from_now.utc.iso8601 }
    assert_equal [ appointments(:sarah_consult).id ], data.map { |a| a["id"] }
  end

  test "filters by status and lead_id" do
    create_appointment(starts_at: 4.days.from_now, status: "tentative")
    michael_id = data["id"]

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { status: "confirmed" }
    assert_equal [ appointments(:sarah_consult).id ], data.map { |a| a["id"] }

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { lead_id: leads(:michael).id }
    assert_equal [ michael_id ], data.map { |a| a["id"] }
  end

  test "a malformed from or to is a 400" do
    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { from: "next tuesday" }
    assert_response :bad_request
    assert_equal "bad_request", error_code
    assert_match(/from/, json.dig("error", "message"))

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { to: "2026-13-45T99:00:00Z" }
    assert_response :bad_request
  end

  test "shows an appointment" do
    get biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob)
    assert_response :ok
    assert_equal leads(:sarah).id, data["lead_id"]
    assert_equal "consultation", data["kind"]
    assert_equal "confirmed", data["status"]
  end

  test "creates an appointment" do
    starts = 5.days.from_now.change(usec: 0)
    assert_difference -> { Appointment.count }, 1 do
      create_appointment(starts_at: starts, kind: "site_visit", location: " 1 Main St ", notes: "Bring ladder",
        assigned_user_id: users(:carol).id)
    end
    assert_response :created
    appointment = Appointment.find(data["id"])
    assert_equal businesses(:acme), appointment.business
    assert_equal leads(:michael), appointment.lead
    assert_equal "site_visit", appointment.kind
    assert_equal "tentative", appointment.status
    assert_equal "1 Main St", appointment.location
    assert_equal users(:carol), appointment.assigned_user
    assert_equal starts, appointment.starts_at
  end

  test "ends_at must be after starts_at" do
    starts = 5.days.from_now
    assert_no_difference -> { Appointment.count } do
      create_appointment(starts_at: starts, ends_at: starts)
    end
    assert_response :unprocessable_content
    assert json.dig("error", "details", "ends_at").present?

    create_appointment(starts_at: starts, ends_at: starts - 1.hour)
    assert_response :unprocessable_content
  end

  test "an appointment can't be longer than 12 hours" do
    starts = 5.days.from_now
    create_appointment(starts_at: starts, ends_at: starts + 12.hours + 1.minute)
    assert_response :unprocessable_content
    assert json.dig("error", "details", "ends_at").present?

    create_appointment(starts_at: starts, ends_at: starts + 12.hours)
    assert_response :created
  end

  test "rejects missing times and invalid kind" do
    post biz_path(:acme, "appointments"), headers: auth_headers(:bob), as: :json,
      params: { appointment: { lead_id: leads(:michael).id, kind: "party" } }
    assert_response :unprocessable_content
    %w[starts_at ends_at kind].each { |f| assert json.dig("error", "details", f).present?, "expected an error on #{f}" }
  end

  test "rejects an assignee who isn't a member" do
    create_appointment(starts_at: 5.days.from_now, assigned_user_id: users(:mallory).id)
    assert_response :unprocessable_content
    assert json.dig("error", "details", "assigned_user").present?
  end

  test "can't book an appointment for another business's lead" do
    assert_no_difference -> { Appointment.count } do
      post biz_path(:acme, "appointments"), headers: auth_headers(:bob), as: :json, params: {
        appointment: { lead_id: leads(:globex_lead).id, starts_at: 5.days.from_now.iso8601, ends_at: (5.days.from_now + 1.hour).iso8601 }
      }
    end
    assert_response :not_found
  end

  test "updates an appointment, validating the new times" do
    path = biz_path(:acme, "appointments", appointments(:sarah_consult).id)
    new_start = 6.days.from_now.change(usec: 0)
    patch path, headers: auth_headers(:bob), as: :json,
      params: { appointment: { starts_at: new_start.iso8601, ends_at: (new_start + 2.hours).iso8601, notes: "Moved" } }
    assert_response :ok
    assert_equal new_start, Time.iso8601(data["starts_at"])
    assert_equal "Moved", data["notes"]

    patch path, headers: auth_headers(:bob), as: :json, params: { appointment: { ends_at: new_start.iso8601 } }
    assert_response :unprocessable_content
    assert_equal new_start + 2.hours, appointments(:sarah_consult).reload.ends_at
  end

  test "the lead can't be changed by update" do
    patch biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob), as: :json,
      params: { appointment: { lead_id: leads(:michael).id, notes: "x" } }
    assert_response :ok
    assert_equal leads(:sarah).id, appointments(:sarah_consult).reload.lead_id
  end

  test "cancelling is a status update; the appointment is kept" do
    patch biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob), as: :json,
      params: { appointment: { status: "cancelled" } }
    assert_response :ok
    assert_equal "cancelled", data["status"]
    assert Appointment.exists?(appointments(:sarah_consult).id)

    get biz_path(:acme, "appointments"), headers: auth_headers(:bob), params: { status: "cancelled" }
    assert_equal [ appointments(:sarah_consult).id ], data.map { |a| a["id"] }

    patch biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob), as: :json,
      params: { appointment: { status: "postponed" } }
    assert_response :unprocessable_content
  end

  test "another business's appointments are 404" do
    get biz_path(:acme, "appointments"), headers: auth_headers(:mallory)
    assert_response :not_found
    get biz_path(:acme, "appointments", appointments(:globex_visit).id), headers: auth_headers(:bob)
    assert_response :not_found
    patch biz_path(:globex, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:mallory), as: :json,
      params: { appointment: { status: "cancelled" } }
    assert_response :not_found
    assert_equal "confirmed", appointments(:sarah_consult).reload.status
  end
end
