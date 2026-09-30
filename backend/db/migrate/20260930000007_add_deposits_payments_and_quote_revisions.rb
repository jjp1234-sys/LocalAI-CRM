# Getting paid, and changing a quote after it's gone out.
#
#   quotes.revision            Q-1001, then Q-1001 rev 2, rev 3... same number
#   quotes.deposit_bps/_cents  a deposit as a percentage or a fixed amount
#   payments                   a request for money: a private link the customer
#                              opens to pay through the business's provider
#   webhook_receipts           payment-provider event IDs already handled, so
#                              a retried webhook can't mark something paid twice
#   businesses.payments_provider / stripe_account_id
#                              where a business's payments go (Stripe Connect)
class AddDepositsPaymentsAndQuoteRevisions < ActiveRecord::Migration[8.1]
  def up
    add_column :quotes, :revision, :integer, null: false, default: 1
    add_column :quotes, :deposit_bps, :integer
    add_column :quotes, :deposit_cents, :bigint
    remove_index :quotes, [ :business_id, :number ]
    add_index :quotes, [ :business_id, :number, :revision ], unique: true
    add_check_constraint :quotes, "revision BETWEEN 1 AND 999", name: "quotes_revision_range"
    add_check_constraint :quotes, "deposit_bps IS NULL OR deposit_bps BETWEEN 1 AND 10000", name: "quotes_deposit_bps_range"
    add_check_constraint :quotes, "deposit_cents IS NULL OR deposit_cents BETWEEN 1 AND 10000000000", name: "quotes_deposit_cents_range"
    add_check_constraint :quotes, "deposit_bps IS NULL OR deposit_cents IS NULL", name: "quotes_one_deposit_kind"

    add_column :businesses, :payments_provider, :string, null: false, default: "none"
    add_column :businesses, :stripe_account_id, :string
    add_check_constraint :businesses, "payments_provider IN ('none', 'simulator', 'stripe')", name: "businesses_payments_provider_valid"
    add_check_constraint :businesses, "stripe_account_id IS NULL OR stripe_account_id ~ '^acct_[A-Za-z0-9]+$'", name: "businesses_stripe_account_format"

    create_table :payments, id: :uuid do |t|
      t.references :business, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :lead_id, null: false
      t.uuid :quote_id
      t.uuid :contract_id
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false, default: "other"
      t.string :description, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "usd"
      t.string :status, null: false, default: "pending"
      t.string :provider, null: false
      # The provider's checkout session, created when the customer clicks Pay.
      t.string :provider_session_id
      t.text :checkout_url
      t.string :token_digest, null: false
      t.text :token # encrypted
      t.datetime :paid_at
      t.timestamps
      t.index :lead_id
      t.index :token_digest, unique: true
      t.index :provider_session_id, unique: true, where: "provider_session_id IS NOT NULL"
      t.index [ :business_id, :status, :paid_at ]
      t.check_constraint "kind IN ('deposit', 'balance', 'other')", name: "payments_kind_valid"
      t.check_constraint "status IN ('pending', 'paid', 'cancelled')", name: "payments_status_valid"
      t.check_constraint "provider IN ('simulator', 'stripe')", name: "payments_provider_valid"
      t.check_constraint "amount_cents BETWEEN 50 AND 10000000000", name: "payments_amount_range"
      t.check_constraint "char_length(description) BETWEEN 1 AND 200", name: "payments_description_length"
      t.check_constraint "(status = 'paid') = (paid_at IS NOT NULL)", name: "payments_paid_consistent"
    end
    add_foreign_key :payments, :leads, column: [ :lead_id, :business_id ], primary_key: [ :id, :business_id ]
    add_foreign_key :payments, :quotes, column: [ :quote_id, :business_id ], primary_key: [ :id, :business_id ]
    add_index :contracts, [ :id, :business_id ], unique: true
    add_foreign_key :payments, :contracts, column: [ :contract_id, :business_id ], primary_key: [ :id, :business_id ]

    execute "ALTER TABLE payments ENABLE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY payments_tenant ON payments
        USING (business_id = current_business_id())
        WITH CHECK (business_id = current_business_id())
    SQL
    # A payment that's been received is a financial record: it can't be
    # edited or deleted afterwards.
    execute <<~SQL
      CREATE FUNCTION forbid_paid_payment_changes() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.paid_at IS NOT NULL THEN
          RAISE EXCEPTION 'payment % is paid and can no longer change', OLD.id;
        END IF;
        RETURN COALESCE(NEW, OLD);
      END $$;

      CREATE TRIGGER payments_frozen_once_paid BEFORE UPDATE OR DELETE ON payments
        FOR EACH ROW EXECUTE FUNCTION forbid_paid_payment_changes();
    SQL

    # Not business data: only the webhook (running as the table owner) uses
    # it, and the app's restricted role has no access at all.
    create_table :webhook_receipts, id: :uuid do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.datetime :created_at, null: false
      t.index [ :provider, :event_id ], unique: true
    end
  end

  def down
    drop_table :webhook_receipts
    execute "DROP TRIGGER IF EXISTS payments_frozen_once_paid ON payments"
    execute "DROP FUNCTION IF EXISTS forbid_paid_payment_changes()"
    execute "DROP POLICY IF EXISTS payments_tenant ON payments"
    drop_table :payments
    remove_index :contracts, [ :id, :business_id ]
    remove_check_constraint :businesses, name: "businesses_stripe_account_format"
    remove_check_constraint :businesses, name: "businesses_payments_provider_valid"
    remove_column :businesses, :stripe_account_id
    remove_column :businesses, :payments_provider
    remove_check_constraint :quotes, name: "quotes_one_deposit_kind"
    remove_check_constraint :quotes, name: "quotes_deposit_cents_range"
    remove_check_constraint :quotes, name: "quotes_deposit_bps_range"
    remove_check_constraint :quotes, name: "quotes_revision_range"
    remove_index :quotes, [ :business_id, :number, :revision ]
    add_index :quotes, [ :business_id, :number ], unique: true
    remove_column :quotes, :deposit_cents
    remove_column :quotes, :deposit_bps
    remove_column :quotes, :revision
  end
end
