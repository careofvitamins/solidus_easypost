module Spree
  module ShipmentDecorator
    def self.prepended(mod)
      mod.state_machine.before_transition(
        to: :shipped,
        do: :buy_easypost_rate,
        if: -> { Spree::EasyPost::CONFIGS[:purchase_labels?] }
      )
    end

    def easypost_shipment
      if selected_easy_post_shipment_id
        @ep_shipment ||= ::EasyPost::Shipment.retrieve(selected_easy_post_shipment_id)
      else
        @ep_shipment = build_easypost_shipment
      end
    end

    def buy_easypost_rate
      return if easypost_shipment.postage_label

      selected_rate = easypost_shipment.rates.find do |rate|
        rate.id == selected_easy_post_rate_id
      end

      easypost_shipment.buy(selected_rate)
      update_local_attributes
    end

    def update_local_attributes
      return unless easypost_shipment

      self.tracking = easypost_shipment.tracking_code
      self.shipping_duration_days = delivery_days_for_selected_rate
      self.estimated_delivery_on = estimated_delivery_date
      self.delivery_status = fetch_delivery_status

      Rails.logger.info "Updated shipment #{id} with tracking number #{tracking}, " \
"shipping duration: #{shipping_duration_days} days, estimated delivery date #{estimated_delivery_on}, " \
"delivery_status: #{delivery_status}"

      true
    end

    def estimated_delivery_date
      tracker = easypost_shipment.tracker
      delivery_event = tracker.tracking_details.detect { |t| t.status == 'delivered' }
      return delivery_event.datetime.to_date if delivery_event

      tracker.est_delivery_date
    end

    private

    def fetch_delivery_status
      tracking_details = easypost_shipment.tracker.tracking_details.last
      return unless tracking_details

      tracking_details.status
    end

    def selected_easy_post_rate_id
      selected_shipping_rate.easy_post_rate_id
    end

    def selected_easy_post_shipment_id
      return unless selected_shipping_rate

      selected_shipping_rate.easy_post_shipment_id
    end

    def build_easypost_shipment
      return unless address

      ::EasyPost::Shipment.create(
        to_address: address.easypost_address,
        from_address: stock_location.easypost_address,
        parcel: to_package.easypost_parcel
      )
    end

    def delivery_days_for_selected_rate
      value = easypost_shipment.selected_rate.delivery_days
      return value if value

      unless value
        Rails.logger.error 'Did not get delivery_days for selected shipping rate. '\
"Shipment: #{easypost_shipment}, defaulting to #{default_shipping_days}"
      end
      nil
    end
  end
end

Spree::Shipment.prepend Spree::ShipmentDecorator
