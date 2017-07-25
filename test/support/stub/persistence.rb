require 'odba/cache'
require 'odba/persistable'
require 'bbmb/model/customer'
require 'bbmb/model/product'

class Object
  def meta_class; class << self; self; end; end
  def meta_eval &blk; meta_class.instance_eval &blk; end
end
module BBMB
  module Persistable
    def Persistable.append_features(mod)
      super
      mod.module_eval do
        alias :__test_initialize__ :initialize
        @instances = []
        def initialize(*args)
          __test_initialize__(*args)
          self.class.instances.push(self)
        end
        class << self
          attr_reader :instances
          def clear_instances
            @instances.clear
          end
          def odba_index(*keys)
            puts "defined odba_index #{keys}"
          end
        def index(*keys)
            index_suffix = keys.join('_and_')
            method_name = sprintf("find_by_%s", index_suffix)
            meta_eval {
              define_method(method_name) { |*vals|
                @instances.find { |instance|
                  vals == keys.collect { |key| instance.send(key) }
                }
              }
            }
          end
        end
      end
    end
  end
  module Model
    class Order
      include Persistable
    end
    class Product
      include Persistable
      index :article_number
      index :ean13
      index :description
      index :pcode
    end
    class Customer
      include Persistable
      index :customer_id
      index :email
      index :ean13
    end
  end
end
module ODBA
  def ODBA.transaction(&block)
    block.call
  end
  module Persistable
    attr_reader :odba_stored
    def odba_store
      @odba_stored = @odba_stored.to_i.next
    end
    def odba_delete
    end
  end
  class Cache
    def retrieve_from_index(index_name, search_term, meta=nil)
      []
    end
    def fetch_named(*args, &block)
      block.call
    end
  end
end
