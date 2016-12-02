module Spree
  module Stock
    module EstimatorDecorator
      # Added here to provide compatibility moving forward with solidus, which
      # as of v1.3.0 changed the Estimator initialization signature to no longer
      # accept arguments.
      #
      # This is added here to allow a version of the easypost gem to be
      # compatible with both pre and post v1.3 versions and initialize
      # an Estimator in the specs
      def initialize(order=nil)
        return unless order
        @order = order
        @currency = order.currency
      end

      def shipping_rates(package)
        shipment = package.easypost_shipment

        log_errors(shipment)

        rates = shipment.rates.sort_by { |r| r.rate.to_i }

        if rates.any?
          spree_rates = rates.map do |rate|
            Spree::ShippingRate.new(
              name: "#{ rate.carrier } #{ rate.service }",
              cost: 8,
              easy_post_shipment_id: rate.shipment_id,
              easy_post_rate_id: rate.id,
              shipping_method: find_or_create_shipping_method(rate)
            )
          end

          # Sets cheapest rate to be selected by default
          if spree_rates.any?
            rate = custom_rate(from: spree_rates, package: package) || spree_rates.min_by(&:cost)
            rate.selected = true
          end

          spree_rates
        else
          []
        end
      end

      private

      def custom_rate(from:, package:)
        special_instructions = package.order.special_instructions
        return unless special_instructions

        special_instruction_chunks = special_instructions.split(' ').map { |instruction| instruction.split(':') }
        return if special_instruction_chunks.empty?

        custom_shipping_method = special_instruction_chunks.to_h.with_indifferent_access[:shipping_method]
        return unless custom_shipping_method

        rate = from.detect{|spree_rate| spree_rate.shipping_method.code == custom_shipping_method}
        return rate if rate

        raise "Unable to find shipping_method (#{custom_shipping_method}) in available shipping methods"
      end

      def log_errors(shipment)
        errors = shipment.messages.select { |message| message.type == 'rate_error' }
        return if errors.empty?

        errors.each { |message| logger.error "Failed to get shipping rate from carrier #{message[:carrier]} because #{message[:message]}, shipment is #{shipment}" }
      end

      def logger
        Rails.logger
      end

      # Cartons require shipping methods to be present, This will lookup a
      # Shipping method based on the admin(internal)_name. This is not user facing
      # and should not be changed in the admin.
      def find_or_create_shipping_method(rate)
        method_name = "#{ rate.carrier } #{ rate.service }"
        Spree::ShippingMethod.find_or_create_by(admin_name: method_name) do |r|
          r.name = method_name
          r.display_on = :both
          r.code = rate.service
          r.calculator = Spree::Calculator::Shipping::FlatRate.create
          r.shipping_categories = [Spree::ShippingCategory.first]
        end
      end
    end
  end
end

Spree::Stock::Estimator.prepend Spree::Stock::EstimatorDecorator
