module Spree
  module Stock
    module PackageDecorator
      class EasyPostAddressError < StandardError
      end
      class EasyPostParcelError < StandardError
      end

      def easypost_parcel
        create_easypost_parcel(Orders::ShipmentProperties.new(order: order).result)
      end

      def create_easypost_parcel(shipment_properties)
        dimensions = shipment_properties.dimensions

        ::EasyPost::Parcel.create(
          length: dimensions.length,
          width: dimensions.width,
          height: dimensions.height,
          weight: shipment_properties.weight,
        )
      rescue ::EasyPost::Error => exception
        raise EasyPostParcelError, "Unable to get EasyPost parcel for weight #{total_weight}"
      end

      def easypost_shipment
        return unless order

        ship_to = order.ship_address
        attributes = {
          from_address: easypost_address_for(stock_location, :stock_location),
          parcel: easypost_parcel,
          options: {
            print_custom_1: order.number,
            print_custom_2: order.queue_code,
            print_custom_3: Time.zone.now.strftime('%m/%d/%Y %H:%M:%S'),
          },
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
