require 'spree_core'
require 'http_logger'

module Spree
  module EasyPost
    CONFIGS = { purchase_labels?: true }
  end
end

require 'easypost'
require 'spree_easypost/engine'
