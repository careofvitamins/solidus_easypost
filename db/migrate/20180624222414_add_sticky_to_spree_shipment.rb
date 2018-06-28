class AddStickyToSpreeShipment < ActiveRecord::Migration[5.2]
  def change
    add_column :spree_shipments, :sticky_shipping, :boolean, null: false, default: false
  end
end
