#!/usr/bin/env ruby
# Model::Order -- bbmb.ch -- 25.09.2006 -- hwyss@ywesee.com

require 'bbmb/model/order'

module BBMB
  module Model
class Order
  class Position
    include ODBA::Persistable
		alias :__old_commit__ :commit!
		def commit!(*args)
			res = __old_commit__(*args)
			odba_store
			res
		end
  end
  include ODBA::Persistable
  ODBA_SERIALIZABLE = ['@unavailable']
  alias :__old_add__ :add
  def add(quantity, product)
    if(pos = __old_add__(quantity, product))
      if(quantity.zero?)
        pos.odba_delete unless BBMB.config.persistence.eql?('none')
      else
        pos.odba_store unless BBMB.config.persistence.eql?('none')
      end
      @positions.odba_store unless BBMB.config.persistence.eql?('none')
      pos
    end
  end
  alias :__old_clear__ :clear
  def clear
    @positions.each { |pos| pos.odba_delete } unless BBMB.config.persistence.eql?('none')
    res = __old_clear__
    @positions.odba_store
    odba_store unless BBMB.config.persistence.eql?('none')
    res
  end
  alias :__old_commit__ :commit!
  def commit!(*args)
    res = __old_commit__(*args)
    odba_store
    res
  end
end
  end
end
