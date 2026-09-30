# Adding someone to a business is now an invitation they have to accept,
# rather than an admin adding any account by email. Without this, any
# business owner could put any user into their business, and learn whether an
# email has an account from the response.
class CreateInvitations < ActiveRecord::Migration[8.1]
  def up
    create_table :invitations, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :email_address, null: false
      t.string :role, null: false, default: "agent"
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :revoked_at
      t.timestamps
      t.index :email_address
      # One open invitation per person per business.
      t.index [ :business_id, :email_address ], unique: true,
        where: "accepted_at IS NULL AND declined_at IS NULL AND revoked_at IS NULL",
        name: "index_invitations_one_open_per_email"
      t.check_constraint "email_address = lower(email_address)", name: "invitations_email_lowercase"
      t.check_constraint "char_length(email_address) <= 254", name: "invitations_email_length"
      t.check_constraint "role IN ('owner', 'admin', 'agent')", name: "invitations_role_valid"
    end

    execute "ALTER TABLE invitations ENABLE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY invitations_tenant ON invitations
        USING (business_id = current_business_id())
        WITH CHECK (business_id = current_business_id())
    SQL
  end

  def down
    execute "DROP POLICY IF EXISTS invitations_tenant ON invitations"
    drop_table :invitations
  end
end
