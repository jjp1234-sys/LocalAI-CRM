# Turns records into the JSON the API returns. Each serializer lists its
# fields explicitly: adding a column to a table never exposes it by accident.
module Serializers
  module_function

  def user(user)
    { id: user.id, name: user.name, email_address: user.email_address }
  end

  def business(business)
    business.slice(:id, :name, :slug, :time_zone, :created_at, :updated_at)
  end

  def membership(membership)
    {
      id: membership.id,
      role: membership.role,
      user: user(membership.user),
      created_at: membership.created_at
    }
  end

  def invitation(invitation)
    invitation.slice(:id, :email_address, :role, :expires_at, :created_at)
  end

  def intake_key(key)
    key.slice(:id, :name, :token_prefix, :last_used_at, :revoked_at, :created_at)
  end

  def lead(lead)
    lead.slice(
      :id, :name, :email, :phone, :need, :source, :status, :score, :external_id,
      :assigned_user_id, :archived_at, :last_activity_at, :created_at, :updated_at
    )
  end

  def conversation(conversation)
    conversation.slice(
      :id, :lead_id, :channel, :status, :assigned_user_id, :last_message_at, :created_at, :updated_at
    )
  end

  def message(message)
    message.slice(:id, :conversation_id, :direction, :sender_kind, :sender_user_id, :body, :created_at)
  end

  def appointment(appointment)
    appointment.slice(
      :id, :lead_id, :assigned_user_id, :kind, :status, :starts_at, :ends_at,
      :location, :notes, :created_at, :updated_at
    )
  end

  def activity(activity)
    activity.slice(:id, :subject_type, :subject_id, :action, :actor_user_id, :details, :created_at)
  end
end
