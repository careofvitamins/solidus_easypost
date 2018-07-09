class AddStickyToSpreeShipment < ActiveRecord::Migration[5.2]
  def change
    add_column :spree_shipments, :stickied_at, :datetime
  end
end
