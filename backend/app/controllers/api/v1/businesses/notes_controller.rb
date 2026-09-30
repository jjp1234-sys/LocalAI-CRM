module Api
  module V1
    module Businesses
      # GET/POST .../leads/:lead_id/notes. Notes can't be edited or deleted.
      class NotesController < BaseController
        before_action { @lead = Lead.find(params[:lead_id]) }

        def index
          records, meta = paginate(@lead.notes)
          render_data records.map { |n| Serializers.note(n) }, meta: meta
        end

        def create
          note = @lead.notes.create!(body: params.expect(note: [ :body ])[:body], author_user: Current.user)
          render_data Serializers.note(note), status: :created
        end
      end
    end
  end
end
