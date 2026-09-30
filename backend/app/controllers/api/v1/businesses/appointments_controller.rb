module Api
  module V1
    module Businesses
      class AppointmentsController < BaseController
        before_action :set_appointment, only: [ :show, :update ]

        # GET .../appointments?from=2026-10-01T00:00:00Z&to=...&status=confirmed&lead_id=...
        # With no filters at all, returns upcoming appointments (the same
        # definition the dashboard summary counts: from now on, not cancelled).
        def index
          from = parse_time(:from)
          to = parse_time(:to)
          status = scalar_param(:status)
          lead_id = scalar_param(:lead_id)

          appointments = from || to || status ? Appointment.all : Appointment.upcoming
          appointments = appointments.where(status: status) if status
          appointments = appointments.where(lead_id: lead_id) if lead_id
          appointments = appointments.where("starts_at >= ?", from || Time.current)
          appointments = appointments.where("starts_at < ?", to) if to

          records, meta = paginate(appointments.order(:starts_at, :id))
          render_data records.map { |a| Serializers.appointment(a) }, meta: meta
        end

        def show
          render_data Serializers.appointment(@appointment)
        end

        def create
          attrs = appointment_params
          appointment = Appointment.create!(attrs.merge(lead: Lead.find(params.require(:appointment).require(:lead_id))))
          render_data Serializers.appointment(appointment), status: :created
        end

        # Cancelling is an update (status: "cancelled"), never a delete.
        def update
          @appointment.update!(appointment_params)
          render_data Serializers.appointment(@appointment)
        end

        private

        def set_appointment
          @appointment = Appointment.find(params[:id])
        end

        def appointment_params
          params.expect(appointment: [ :kind, :status, :starts_at, :ends_at, :location, :notes, :assigned_user_id ])
        end

        def parse_time(key)
          value = scalar_param(key)
          return nil unless value

          time = Time.iso8601(value)
          raise ArgumentError unless Appointment::YEARS.cover?(time.year)

          time
        rescue ArgumentError
          raise ActionController::BadRequest, "#{key} must be an ISO 8601 time between years #{Appointment::YEARS.minmax.join(' and ')}, like 2026-10-01T09:00:00Z"
        end
      end
    end
  end
end
