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

      begin
        force_refresh_rates if ENV['feature_refresh_rates_on_label_purchase'] == 'true'
        buy_rate
      rescue => error
        raise error unless error.code == 'SHIPMENT.POSTAGE.FAILURE'

        force_refresh_rates
        buy_rate
      end
    end

    def update_local_attributes
      self.assign_attributes(
        delivery_status: easypost_delivery_status,
        easypost_tracking_url: easypost_public_url,
        estimated_delivery_on: estimated_delivery_date,
        shipping_duration_days: delivery_days_for_selected_rate,
        tracking: easypost_tracking_code,
      )
    end

    def estimated_delivery_date
      return if EasyPostTools.test_mode?
      return unless easypost_tracker

      delivery_event = easypost_tracker.tracking_details.detect { |t| t.status == 'delivered' }

      return delivery_event.datetime.to_date if delivery_event

      easypost_tracker.est_delivery_date
    end

    def easypost_delivery_status
      return unless easypost_tracker

      easypost_tracker.status
    end

    def easypost_public_url
      return unless easypost_tracker

      easypost_tracker.public_url
    end

    def easypost_tracking_code
      return unless easypost_tracker

      easypost_tracker.tracking_code
    end

    def easypost_tracker
      return unless easypost_shipment

      easypost_shipment.tracker
    end

    def fetch_delivery_status
      tracker = easypost_shipment.tracker
      return unless tracker

      tracking_details = tracker.tracking_details.last
      return unless tracking_details

      tracking_details.status
    end

    def delivery_days_for_selected_rate
      selected_rate = easypost_shipment.selected_rate
      return unless selected_rate

      value = selected_rate.delivery_days
      return value if value

      unless value
        Rails.logger.error 'EasyPost Shipment: Did not get delivery_days for selected shipping rate. '\
"Shipment: #{easypost_shipment}"
      end
      nil
    end

    def stickied_shipping_method_name
      return unless stickied_at

      shipping_method.name
    end

    def select_stickied_method(rates)
      stickied_rate = rates.detect { |rate| rate.name == stickied_shipping_method_name }
      return unless stickied_rate

      rates.each { |rate| rate.selected = rate == stickied_rate }
    end

    def force_refresh_rates
      easypost_shipment.get_rates
      new_rates = Spree::Config.stock.estimator_class.new.shipping_rates(to_package)

      select_stickied_method(new_rates) if stickied_shipping_method_name

      return unless new_rates.any?(&:selected)

      self.shipping_rates = new_rates
      save!
      @ep_shipment = nil
    end

    private

    def buy_rate
      selected_rate = easypost_shipment.rates.find do |rate|
        rate.id == selected_easy_post_rate_id
      end

      Rails.logger.info "EasyPost Shipment: Buying rate for #{id}"
      easypost_shipment.buy(selected_rate)
      update_local_attributes
    end

    def selected_easy_post_rate_id
      selected_shipping_rate.easy_post_rate_id
    end

    def selected_easy_post_shipment_id
      return unless selected_shipping_rate

      selected_shipping_rate.easy_post_shipment_id
    end

    def build_easypost_shipment
      return unless order.ship_address

      ship_to = order.ship_address.easypost_address
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
      Rails.logger.info "EasyPost Shipment: Created shipment to #{ship_to.id} with attributes #{attributes}"

      shipment
    end
  end
end

Spree::Shipment.prepend Spree::ShipmentDecorator
