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
require 'bbmb/util/server'

module BBMB
  def self.persistence
    @@persistence ||= BBMB::Persistence::ODBA
  end
  module Util
    class App < SBSM::App
      attr_accessor :db_manager, :yus_server
      def start_service
        case BBMB.config.persistence
        when 'odba'
          DRb.install_id_conv ODBA::DRbIdConv.new
          BBMB.persistence = BBMB::Persistence::ODBA
        end
        BBMB.auth = DRb::DRbObject.new(nil, BBMB.config.auth_url)
        puts "installed BBMB.auth for #{BBMB.config.auth_url}"
        BBMB.server = BBMB::Util::Server.new(BBMB.persistence, self)
        BBMB.server.extend(DRbUndumped)
        BBMB.server = BBMB.server
        puts "installed BBMB.server #{BBMB.server}"
        if(BBMB.config.update?)
          BBMB.server.run_updater
        end
        if(BBMB.config.invoice?)
          BBMB.server.run_invoicer
        end
        url = BBMB.config.server_url
        url.untaint
        DRb.start_service(url, BBMB.server)
        $SAFE = 1
        $0 = BBMB.config.name
        SBSM.logger.info('start') { sprintf("starting bbmb-server on %s", url) }
        DRb.thread.join
        SBSM.logger.info('finished') { sprintf("starting bbmb-server on %s", url) }
      rescue Exception => error
        SBSM.logger.error('fatal') { error }
        raise
      end
      def initialize
          super
          puts "Starting Rack-Service #{self.class} and service #{BBMB.config.server_url}"
          Thread.new {
              start_service
          }
      end
    end
  end
end