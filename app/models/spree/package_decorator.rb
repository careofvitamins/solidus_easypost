module Spree
  module Stock
    module PackageDecorator
      class EasyPostAddressError < StandardError
      end
      class EasyPostParcelError < StandardError
      end

      def easypost_parcel
        total_weight = 18

        create_easypost_parcel(total_weight)
      end

      def create_easypost_parcel(total_weight)
        ::EasyPost::Parcel.create weight: total_weight
      rescue ::EasyPost::Error => exception
        raise EasyPostParcelError, "Unable to get EasyPost parcel for weight #{total_weight}"
      end

      def easypost_shipment
        return unless order

        ship_to = order.ship_address
        attributes = {
          from_address: easypost_address_for(stock_location, :stock_location),
          parcel: easypost_parcel,
          print_custom_1: order.number,
          print_custom_2: order.queue_code,
          print_custom_3: Time.zone.now.strftime('%m/%d/%Y %H:%M:%S'),
          to_address: easypost_address_for(ship_to, :order_ship_address),
        }
        shipment = ::EasyPost::Shipment.create(attributes)
        Rails.logger.info "EasyPost Shipment: Created shipment to #{ship_to.attributes} with attributes #{attributes}"

        shipment
      end

      private

      def easypost_address_for(address, purpose)
        raise "Address for #{purpose} is nil" unless address

        address.easypost_address
      rescue ::EasyPost::Error => exception
        raise EasyPostAddressError, "Unable to get #{purpose} EasyPost address for #{address.easypost_attributes}"
      end
    end
  end
end

Spree::Stock::Package.prepend Spree::Stock::PackageDecorator
