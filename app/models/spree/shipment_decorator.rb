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
      Rails.logger.info "Bought EasyPost shipment with tracking number #{tracking}, " \
"shipping duration: #{shipping_duration_days} days, estimated delivery date #{estimated_delivery_on}"
    end

    def update_local_attributes
      self.tracking = easypost_shipment.tracking_code
      self.shipping_duration_days = delivery_days_for_selected_rate
      self.estimated_delivery_on = easypost_shipment.tracker.est_delivery_date
    end

    private

    def selected_easy_post_rate_id
      selected_shipping_rate.easy_post_rate_id
    end

    def selected_easy_post_shipment_id
      return unless selected_shipping_rate

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

      unless value
        Rails.logger.error 'Did not get delivery_days for selected shipping rate. '\
"Shipment: #{easypost_shipment}, defaulting to #{default_shipping_days}"
      end
      nil
    end
  end
end

Spree::Shipment.prepend Spree::ShipmentDecorator
