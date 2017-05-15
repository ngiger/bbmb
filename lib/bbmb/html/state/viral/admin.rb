#!/usr/bin/env ruby
# Html::State::Viral::Admin -- bbmb.ch -- 18.09.2006 -- hwyss@ywesee.com

require 'bbmb/html/state/customer'
require 'bbmb/html/state/customers'
require 'bbmb/html/state/orders'
require 'bbmb/html/state/history'
require 'sbsm/viralstate'

module BBMB
  module Html
    module State
      module Viral
module Admin
	include SBSM::ViralState
  EVENT_MAP = {
    :customers	=>	State::Customers,
    :customer   =>  State::Customer,
    :history    =>  State::History,
    :orders     =>  State::Orders,
  }
  def _customer(customer_id = @session.user_input(:customer_id))
    Model::Customer.find_by_customer_id(customer_id)
  end
  def home
    home = @session.user.get_preference(:home) || :customers
    trigger(home)
  end
  def order
    if(order_id = @session.user_input(:order_id))
      customer_id, commit_id = order_id.split('-', 2)
      State::Order.new(@session, _customer(customer_id).order(commit_id))
    end
  end
  def zone_navigation
    [:customers]
  end
end
      end
    end
  end
end
