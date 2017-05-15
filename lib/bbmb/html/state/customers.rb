require 'ostruct'
require 'bbmb/html/state/global_predefine'
require 'bbmb/html/state/customer'
require 'bbmb/html/view/customers'
require 'bbmb/model/customer'

module BBMB
  module Html
    module State
      class Customers < Global
        DIRECT_EVENT = :customers
        VIEW         = View::Customers
        FILTER       = %i{customer_id ean13 organisation plz city email}

        def init
          start = Time.now
          @model  = BBMB.persistence.all(Model::Customer)
          @sortby = [:organisation]
          SBSM.debug('State') {
            sprintf("Customers#init: loaded %i customers in %1.5fs",
                    @model.size, Time.now - start)
          }
          @filter = make_filter
        end

        private

        def make_filter
          Proc.new { |model|
            input = @session.event_bound_user_input(:filter)
            if input
              pattern = Regexp.new(input.gsub('*', '.*'), 'ui')
              model = model.select { |customer|
                FILTER.any? { |key|
                  value = customer.send(key).to_s
                  next if value.empty?
                  begin; pattern.match(value); rescue ArgumentError; false; end
                }
              }
            end
            get_sortby!
            if @sortby.include?(:valid) || @sortby.include?(:last_login)
              # decorates customer objects with (yus) session
              model = model.map { |m| CustomerDecorator.new(m, @session) }
            end
            model.sort! { |a, b| compare_entries(a, b) }
            @sort_reverse && model.reverse!
            page(model)
          }
        end

        def page(model)
          index = @session.user_input(:index).to_i
          step  = @session.user.get_preference(:pagestep) || BBMB.config.pagestep
          page = OpenStruct.new
          page.index     = index
          page.first     = index + 1
          page.step      = step
          page.total     = model.size
          page.customers = model[index, step]
          page.last      = index + page.customers.size
          page
        end
      end

      class CustomerDecorator < SimpleDelegator

        def initialize(model, session)
          @source  = model
          @session = session
          self.__setobj__(@source)
        end

        def last_login
          @last_login ||= @session.user.last_login(email)
        end

        def valid
          @valid ||= @session.user.entity_valid?(email).to_s
        end
      end
    end
  end
end
