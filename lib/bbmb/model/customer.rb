#!/usr/bin/env ruby
# Model::Customer -- bbmb.ch -- 14.09.2006 -- hwyss@ywesee.com

require 'thread'
require 'bbmb/model/order'

module BBMB
  module Model
class Customer
  MUTEX = Mutex.new

  attr_reader :customer_id, :email, :archive, :quotas
  attr_accessor :address1, :address2, :address3, :canton, :city,
    :drtitle, :ean13, :fax, :firstname, :language, :lastname,
    :organisation, :phone_business, :phone_mobile, :phone_private, :plz,
    :status, :title, :terms_last_accepted, :order_confirmation
  def initialize(customer_id, email=nil)
    @archive = {}
    self.customer_id = customer_id if customer_id
    @email = email
    @favorites = Order.new(self)
    @protected = {}
    @quotas = []
  end
  def add_quota(quota)
    unless @quotas.is_a?(Array)
      puts "customer #{customer_id}: Fixing quotas #{@quotas} -> []"
      @quotas = []
      odba_store;
    end
    @quotas.push(quota).uniq!
    quota
  end
  def address_lines
    [
      @organisation,
      [@drtitle, @firstname, @lastname].compact.join(' '),
      @address1,
      @address2,
      @address3,
      [@plz, @city].compact.join(' '),
    ].compact
  end
  def commit_order!(commit_time = Time.now)
    MUTEX.synchronize {
      id = @archive.keys.max.to_i.next
      order = current_order
      order.commit!(id, commit_time)
      @archive.store(id, order)
      @current_order = nil
      order
    }
  end
  def current_order
    @current_order ||= Order.new(self)
  end
  def customer_id=(customer_id)
    if other = Customer.find_by_customer_id(customer_id)
      raise "Duplicate customer_id #{customer_id}"
    else
      @customer_id = customer_id
    end
  end
  def quota(article_id)
    @quotas.compact.find { |quota| quota.article_number == article_id }
  end
  def email=(email)
    if(@email || email)
      raise "Invalid email address: nil" unless email
      return if @email.eql?(email)
      email = email.encode('UTF-8')
      ## notify the server of this change, as it affects the user-data
      BBMB.server.rename_user(@email, email)
      @email = email
    end
  end
  def favorites
    @favorites ||= Order.new(self)
  end
  def inject_order(order, commit_time = Time.now)
    MUTEX.synchronize {
      id = @archive.keys.max.to_i.next
      order.commit!(id, commit_time)
      @archive.store(id, order)
      order
    }
  end
  def order(commit_id)
    @archive[commit_id.to_i]
  end
  def orders
    @archive.values
  end
  def protect!(key)
    @protected.store(key, true)
  end
  def protects?(key)
    @protected.fetch(key, false)
  end
  def turnover
    orders.inject(0) do
      |memo, order|
      begin
        order.total + memo
      rescue => error
        SBSM.info "turnover error for #{order.order_id} returning memo"
        memo
      end
    end
  end
end
  end
end
