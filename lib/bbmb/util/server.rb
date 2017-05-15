#!/usr/bin/env ruby
# Util::Server -- de.bbmb.org -- 01.09.2006 -- hwyss@ywesee.com

require 'bbmb/config'
require 'bbmb/html/util/known_user'
require 'bbmb/html/util/session'
require 'bbmb/html/util/validator'
require 'bbmb/util/invoicer'
require 'bbmb/util/invoicer'
require 'bbmb/util/mail'
require 'bbmb/util/updater'
require 'bbmb/model/order' # needed to be enable to invoice later
require 'bbmb/model/customer'
require 'date'
require 'sbsm/app'
require 'bbmb/persistence/odba'
require 'bbmb/model/customer'
require 'bbmb/model/quota'
require 'bbmb/model/product'
require 'bbmb/model/promotion'

module BBMB
  def self.persistence
    @@persistence ||= BBMB::Persistence::ODBA
  end
  module Util
    class Server
      def initialize(persistence, app)
        puts "Self #{self.class} initialize"
        @persistence = persistence
        @app = app
      end
      def update
        Updater.run
      rescue Exception => e
        Mail.notify_error(e)
      end
    end
    class RackInterface < SBSM::RackInterface
      ENABLE_ADMIN = true
      SESSION = Html::Util::Session
      VALIDATOR = Html::Util::Validator
      attr_reader :updater, :auth
      def initialize(app: BBMB::Util::App.new,
                     auth: nil,
                     validator: BBMB::Html::Util::Validator)
        [ File.join(Dir.pwd, 'etc', 'config.yml'),
        ].each do |config_file|
          if File.exist?(config_file)
            puts "BBMB.config.load from #{config_file}"
            BBMB.config.load (config_file)
            break
          end
        end
        @auth = DRb::DRbObject.new(nil, BBMB.config.auth_url)
        puts "@auth is #{@auth} from #{self.class}"
        @app = app
        super(app: app,
              session_class: BBMB::Html::Util::Session,
              unknown_user: Html::Util::KnownUser,
              validator: validator,
              cookie_name: 'virbac.bbmb'
              )
      end
      if false
      def inject_order(customer_id, products, infos, opts={})
        @app.inject_order(customer_id, products, infos, opts)
      end
      def run_invoicer
        @app.run_invoicer
      end
      def run_updater
        @app.run_updater
      end
      def rename_user(old_name, new_name)
        @app.rename_user(old_name, new_name)
      end
      end
      def inject_order(customer_id, products, infos, opts={})
        customer = Model::Customer.find_by_customer_id(customer_id) \
          || Model::Customer.find_by_ean13(customer_id)
        needed_create = false
        unless customer
          if idtype = opts[:create_missing_customer] && !customer_id.empty?
            customer = Model::Customer.new(customer_id)
            if idtype.to_s == 'ean13'
              customer.ean13 = customer_id
            end
            BBMB.persistence.save(customer)
            needed_create = true
          else
            raise "Unknown Customer #{customer_id}"
          end
        end
        order = Model::Order.new(customer)
        products.each { |info|
          if(product = Model::Product.find_by_pcode(info[:pcode]) \
              || Model::Product.find_by_ean13(info[:ean13]) \
              || Model::Product.find_by_article_number(info[:article_number]))
            order.add(info[:quantity], product)
            [:article_number, :backorder].each do |key|
              info.store key, product.send(key)
            end
            info.store :description, product.description.de
            info[:deliverable] = info[:quantity]
          else
            info[:deliverable] = 0
          end
        }
        infos.each { |key, value|
          order.send("#{key}=", value)
        }
        customer.inject_order(order)
        if opts[:deliver]
          async do
            send_order order, customer
          end
        end
        if needed_create
          BBMB::Util::Mail.notify_inject_error(order, opts)
        end
        { :order_id => order.order_id, :products => products }
      end
      def invoice(range)
        Invoicer.run(range)
      rescue Exception => e
        Mail.notify_error(e)
      end
      def login(email, pass)
          session = BBMB.auth.login(email, pass, BBMB.config.auth_domain)
          Html::Util::KnownUser.new(session)
        end
        def logout(session)
          BBMB.auth.logout(session)
        rescue DRb::DRbError, RangeError, NameError
        end
      def rename_user(old_name, new_name)
        return if old_name.eql?(new_name)
        BBMB.auth.autosession(BBMB.config.auth_domain) do |session|
          if(old_name.nil?)
            session.create_entity(new_name)
          else
            session.rename(old_name, new_name)
          end
        end
      end
      def run_invoicer
        SBSM.debug("run_invoicer starting")
        @invoicer ||= Thread.new {
          Thread.current.abort_on_exception = true
          loop {
            today = Date.today
            day = today >> 1
            start = Time.local(today.year, today.month)
            now = Time.now
            at = Time.local(day.year, day.month)
            secs = at - now
            SBSM.debug("invoicer") {
              "sleeping %.2f seconds" % secs
            }
            sleep(secs)
            SBSM.debug("invoice starting")
            invoice(start...at)
            SBSM.debug("invoice finished")
          }
        }
      end
      def run_updater
        run_only_once_at_startup = false
        SBSM.debug("updater") { "run_updater run_only_once_at_startup? #{run_only_once_at_startup} " }
        @updater ||= Thread.new {
          loop {
            day = Date.today
            now = Time.now
            if(now.hour >= BBMB.config.update_hour)
              day += 1
            end
            at = Time.local(day.year, day.month, day.day, BBMB.config.update_hour)
            secs = at - now
            SBSM.debug("updater") { "sleeping %.2f seconds. run_only_once_at_startup #{run_only_once_at_startup}" % secs  }
            if run_only_once_at_startup then puts "Skipped sleeping #{secs}" else sleep(secs) end

            SBSM.debug("update starting")
            update
            SBSM.debug("update finished")
            Thread.abort if run_only_once_at_startup
          }
        }
      end
      def send_order order, customer
        begin
          Timeout.timeout(300) {
            BBMB::Util::TargetDir.send_order(order)
          }
        rescue StandardError => err
          err.message << " (Email: #{customer.email} - Customer-Id: #{customer.customer_id})"
          BBMB::Util::Mail.notify_error(err)
        end
        begin
          Timeout.timeout(300) {
            BBMB::Util::Mail.send_order(order)
          }
        rescue StandardError => err
          err.message << " (Email: #{customer.email} - Customer-Id: #{customer.customer_id})"
          BBMB::Util::Mail.notify_error(err)
        end
        begin
          Timeout.timeout(300) {
            BBMB::Util::Mail.send_confirmation(order)
          }
        rescue StandardError => err
          err.message << " (Email: #{customer.email} - Customer-Id: #{customer.customer_id})"
          BBMB::Util::Mail.notify_error(err)
        end
      end
      def update
        Updater.run
      rescue Exception => e
        Mail.notify_error(e)
      end
    end
    class App < SBSM::App
      def login(email, pass)
        session = BBMB.auth.login(email, pass, BBMB.config.auth_domain)
        Html::Util::KnownUser.new(session)
      end
      def logout(session)
        # Here we start when logging in from the home page
        BBMB.auth.logout(session)
      rescue DRb::DRbError, RangeError, NameError
      end
    end
      end
      end
