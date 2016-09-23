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

      rate = easypost_shipment.rates.find do |rate|
        rate.id == selected_easy_post_rate_id
      end

      easypost_shipment.buy(rate)
      self.tracking = easypost_shipment.tracking_code
      self.shipping_duration_days = delivery_days_for_selected_rate
    end

    private

    def selected_easy_post_rate_id
      selected_shipping_rate.easy_post_rate_id
    end

    def selected_easy_post_shipment_id
      selected_shipping_rate.easy_post_shipment_id
    end

    def build_easypost_shipment
      ::EasyPost::Shipment.create(
        to_address: address.easypost_address,
        from_address: stock_location.easypost_address,
        parcel: to_package.easypost_parcel
      )
    end

    def delivery_days_for_selected_rate
      value = easypost_shipment.selected_rate.delivery_days
      return value if value

      Rails.logger.error "Did not get delivery_days for selected shipping rate. Shipment: #{easypost_shipment}" unless value
      4
    end
  end
end

Spree::Shipment.prepend Spree::ShipmentDecorator
