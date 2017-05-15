#!/usr/bin/env ruby
# Util::Updater -- bbmb.ch -- 14.09.2006 -- hwyss@ywesee.com

require 'bbmb'
require 'bbmb/util/polling_manager'

module BBMB
  module Util
module Updater
  def Updater.run
    PollingManager.new.poll_sources do |filename, io|
      importer, *args = BBMB.config.importers[filename]
      if(importer)
        import(importer, args, io)
      end
    end
  end
  def Updater.import(importer, args, io)
    klass = Util.const_get(importer)
    count = klass.new(*args).import(io)
    SBSM.info('updater') { sprintf("%s imported %i entities", importer.class, (count && count.defined?(:to_i)) ? count.to_i : 0) }
  end
end
  end
end
