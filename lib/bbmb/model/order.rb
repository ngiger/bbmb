#!/usr/bin/env ruby
# Model::Order -- bbmb.ch -- 22.09.2006 -- hwyss@ywesee.com

require 'bbmb/config'
require 'bbmb/util/numbers'
require 'csv'

module BBMB
  module Model
class Order
  class Info
    include Util::Numbers
    attr_accessor :ean13, :pcode, :description
    int_accessor :quantity
  end
  class Position
    include Util::Numbers
    attr_reader :product
    int_accessor :quantity
    money_accessor :price_effective
    def initialize(quantity, product)
      @quantity = quantity
      @product = product
    end
    def commit!
      @product = @product.to_info
    end
    def freebies
      if(promo = @product.current_promo)
        promo.freebies(@quantity)
      end
    end
    def method_missing(name, *args, &block)
      @product.send(name, *args, &block) if @product
    end
    def price
      @price_effective || price_effective
    end
    def price_effective(qty = @quantity)
      @product.price_effective(qty)
    end
    def price_qty(qty = @quantity)
      @product.price_qty(qty) if @product
    end
    def total
      price * @quantity
    end
    def respond_to?(name)
      super || @product.respond_to?(name)
    end
  end
  include Enumerable
  include Util::Numbers
  attr_reader :commit_id, :commit_time, :customer, :positions, :unavailable
  attr_accessor :comment, :reference
  int_accessor :priority
  money_accessor :shipping
  def initialize(customer)
    @customer = customer
    @positions = []
    @unavailable = []
  end
  def add(quantity, product)
    pos = nil
    if(pos = position(product))
      if(quantity.zero?)
        @positions.delete(pos)
      else
        pos.quantity = quantity
      end
    elsif(quantity.nonzero?)
      pos = Position.new(quantity, product)
      @positions.push(pos)
    end
    if(pos && quantity.nonzero?)
      pos.price_effective = price_effective(pos)
    end
    pos
  end
  def additional_info
    info = {}
    [ :comment, :priority, :reference ].each { |key|
      if(value = self.send(key))
        info.store(key, value)
      end
    }
    info
  end
  def calculate_effective_prices
    @positions.each { |pos|
      pos.price_effective = price_effective(pos)
    }
  end
  def clear
    @positions.clear
    @unavailable.clear
  end
  def commit!(commit_id, commit_time)
    raise "can't commit empty order" if(empty?)
    calculate_effective_prices
    @positions.each { |pos|
      pos.commit!
    }
    @unavailable.clear
    @commit_time = commit_time
    @commit_id = commit_id
  end
  def each(&block)
    @positions.each(&block)
  end
  def empty?
    @positions.empty?
  end
  def filename
    sprintf("%s-%s.txt", order_id, @commit_time.strftime('%Y%m%d%H%M%S'))
  end
  def increment(quantity, product)
    if(pos = position(product))
      quantity += pos.quantity
    end
    add(quantity, product)
  end
  def item_count
    @positions.inject(0) { |memo, pos| memo + pos.quantity }
  end
  def i2_body
    lines = []
    offset = 1
    @positions.each_with_index { |position, idx|
      lines.push *i2_position(idx + offset, position, position.quantity)
      if(freebies = position.freebies)
        offset += 1
        lines.push *i2_position(idx + offset, position, freebies)
        lines.push "603:21"
      end
    }
    lines.join("\n")
  end
  def i2_header
    lines = [
      "001:7601001000681",
      "002:ORDERX",
      "003:220",
      "010:%s" % filename,
      "100:%s" % BBMB.config.i2_100,
      "101:%s" % @reference,
      "201:CU",
      "202:%s" % @customer.customer_id,
      "201:BY",
      "202:1075",
      "231:%s" % @customer.organisation,
    ]
    if(@comment && !@comment.empty?)
      lines.push "236:%s" % _formatted_comment
    end
    lines.push "237:61"
    if(@priority)
      lines.push "238:%i" % @priority
    end
    lines.push "250:ADE",
                sprintf("251:%i%05i", @customer.customer_id, @commit_id),
                "300:4", "301:%s" % @commit_time.strftime('%Y%m%d')
    lines.join("\n")
  end
  def i2_position(line, position, quantity)
    ["500:%i" % line,
      "501:%s" % position.ean13,
      "502:%s" % position.article_number,
      "520:%s" % quantity,
      "521:PCE", "540:2", "541:%s" % @commit_time.strftime('%Y%m%d')]
  end
  def order_id
    sprintf "%s-%s", @customer.customer_id, @commit_id
  end
  def position(product)
    @positions.find { |pos| pos.product == product }
  end
  def price_effective(pos)
    ((quota = quota(pos.article_number)) && quota.price) \
      || pos.price_effective
  end
  def quantity(product)
    if(pos = position(product))
      pos.quantity
    else
      0
    end
  end
  def quota(article_number)
    @customer.quota(article_number)
  end
  def reverse!
    @positions.reverse!
  end
  def size
    @positions.size
  end
  def sort!(*args, &block)
    @positions.sort!(*args, &block)
  end
  def sort_by(*args, &block)
    twin = dup
    twin.positions.replace @positions.sort_by(*args, &block)
    twin
  end
  def total
    @positions.inject(@shipping) { |memo, pos| pos.total + memo }
  rescue
    SBSM.info "total: rescuing by adding 0 to memo #{memo} as total for #{order_id}"
    return memo
  end
  def total_incl_vat
    if rate = BBMB.config.vat_rate
      total * (100 + rate.to_f) / 100
    end
  end
  def to_csv
    result = ''
    BBMB.config.target_format_fs ||= ','
    BBMB.config.target_format_rs ||= "\n"
    CSV.generate(result, { :col_sep => BBMB.config.target_format_fs,
                           :row_sep => BBMB.config.target_format_rs}) { |writer|
      @positions.each { |position|
        writer << [
          @customer.customer_id,
          @customer.ean13,
          @commit_time.strftime('%d%m%Y'),
          @commit_id,
          position.pcode,
          position.ean13,
          position.article_number,
          position.quantity,
          position.price,
          @reference,
          _formatted_comment(' '),
        ]
      }
    }
    result
  end
  def to_i2
    i2_header << "\n" << i2_body << "\n"
  end
  def to_target_format
    self.send("to_#{BBMB.config.target_format}")
  end
  def vat
    if rate = BBMB.config.vat_rate
      total * rate.to_f / 100
    end
  end
  private
  def _formatted_comment(replacement=';')
    @comment.to_s.gsub(/[\r\n]+/, replacement)[0,60] if @comment
  end
end
  end
end
