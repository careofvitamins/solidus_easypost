module Spree
  module ShipmentDecorator
    def self.prepended(mod)
      mod.state_machine.before_transition(
        to: :shipped,
        do: :buy_easypost_rate,
        if: -> { Spree::EasyPost::CONFIGS[:purchase_labels?] },
      )
    end

    def easypost_shipment
      if selected_easy_post_shipment_id
        Rails.logger.info "EasyPost Shipment: Retrieving info for #{selected_easy_post_shipment_id}"
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

      Rails.logger.info "EasyPost Shipment: Buying rate for #{id}"
      easypost_shipment.buy(selected_rate)
      update_local_attributes
    end

    def update_local_attributes
      Shipments::UpdateEasypost.new(shipment: self).perform
    end

    def estimated_delivery_date
      return if EasyPostTools.test_mode?

      tracker = easypost_shipment.tracker
      delivery_event = tracker.tracking_details.detect { |t| t.status == 'delivered' }

      return delivery_event.datetime.to_date if delivery_event

      tracker.est_delivery_date
    end

    def fetch_delivery_status
      tracking_details = easypost_shipment.tracker.tracking_details.last
      return unless tracking_details

      tracking_details.status
    end

    def delivery_days_for_selected_rate
      value = easypost_shipment.selected_rate.delivery_days
      return value if value

      unless value
        Rails.logger.error 'EasyPost Shipment: Did not get delivery_days for selected shipping rate. '\
"Shipment: #{easypost_shipment}"
      end
      nil
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
      return unless address

      ship_to = address.easypost_address
      attributes = {
        from_address: stock_location.easypost_address,
        parcel: to_package.easypost_parcel,
        options: {
          print_custom_1: order.number,
          print_custom_2: order.queue_code,
          print_custom_3: Time.zone.now.strftime('%m/%d/%Y %H:%M:%S'),
        },
        to_address: ship_to,
      }
      shipment = ::EasyPost::Shipment.create(attributes)
      Rails.logger.info "EasyPost Shipment: Created shipment to #{ship_to.attributes} with attributes #{attributes}"

      shipment
    end
  end
end

Spree::Shipment.prepend Spree::ShipmentDecorator
