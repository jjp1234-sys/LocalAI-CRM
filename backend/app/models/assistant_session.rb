# What one staff member's chat with the assistant is in the middle of:
#   "list"     the lead IDs last shown as a numbered list, so "lead 2" works
#   "pendings" questions waiting for an answer (confirm a booking, what to do
#              with a returning customer), keyed by a one-time nonce that the
#              answer buttons carry. Each expires after PENDING_TTL.
class AssistantSession < ApplicationRecord
  include TenantOwned

  PENDING_TTL = 10.minutes
  PENDING_LIMIT = 10

  belongs_to :user

  def self.for(user)
    find_or_create_by!(user: user)
  rescue ActiveRecord::RecordNotUnique
    find_by!(user: user)
  end

  def list
    Array(state["list"])
  end

  def remember_list!(ids)
    update!(state: state.merge("list" => ids.first(20)))
  end

  # The follow-ups last shown by "tasks", so "done 2" works.
  def tasks
    Array(state["tasks"])
  end

  def remember_tasks!(ids)
    update!(state: state.merge("tasks" => ids.first(20)))
  end

  # Stores a question and returns the nonce its answer buttons should carry.
  # replacing: drop any waiting questions of this kind first.
  def add_pending!(action, ttl: PENDING_TTL, replacing: nil)
    nonce = SecureRandom.hex(6)
    entries = live_pendings
    entries = entries.reject { |_, a| a["action"] == replacing } if replacing
    entries = entries.merge(nonce => action.merge("expires_at" => ttl.from_now.iso8601, "added_at" => Time.current.iso8601))
    entries = entries.sort_by { |_, a| a["added_at"] }.last(PENDING_LIMIT).to_h
    update!(state: state.merge("pendings" => entries))
    nonce
  end

  # Removes and returns the question with this nonce, if it's still live.
  def take_pending!(nonce)
    entries = live_pendings
    action = entries.delete(nonce.to_s)
    update!(state: state.merge("pendings" => entries)) if action
    action
  end

  # The most recent live question of a kind: what a typed "yes" answers.
  def latest_pending(action_name)
    live_pendings.select { |_, a| a["action"] == action_name }.max_by { |_, a| a["added_at"] }
  end

  private

  def live_pendings
    raw = state["pendings"].is_a?(Hash) ? state["pendings"] : {}
    raw.select { |_, a| a.is_a?(Hash) && a["expires_at"] && Time.iso8601(a["expires_at"]) > Time.current }
  end
end
