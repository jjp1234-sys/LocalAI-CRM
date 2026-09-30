module Api
  module V1
    module Businesses
      # Keys for posting leads from outside (website forms, webhooks).
      # The full key is returned once, when it's created. After that only its
      # first few characters are shown, so you can tell keys apart.
      class IntakeKeysController < BaseController
        require_role :admin

        def index
          records, meta = paginate(IntakeKey.order(created_at: :desc, id: :desc))
          render_data records.map { |k| Serializers.intake_key(k) }, meta: meta
        end

        def create
          key = IntakeKey.create!(name: params.expect(intake_key: [ :name ])[:name], created_by: Current.user)
          render_data Serializers.intake_key(key).merge(token: key.token), status: :created
        end

        # Revokes the key. It stays listed, marked revoked, for the record.
        def destroy
          IntakeKey.find(params[:id]).revoke!
          head :no_content
        end
      end
    end
  end
end
