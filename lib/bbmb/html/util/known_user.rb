#!/usr/bin/env ruby
# Html::Util::KnownUser -- bbmb.ch -- 18.09.2006 -- hwyss@ywesee.com

require 'sbsm/user'

module BBMB
  module Html
    module Util
class KnownUser < SBSM::User
  ### Admin users need permissions for:
  # login BBMB.config.auth_domain + ".Admin"
  # edit yus.entities
  # set_password
  # grant login
  #
  ### Customers need permissions for:
  # login BBMB.config.auth_domain + ".Customer"
  attr_reader :auth_session
  PREFERENCE_KEYS = [ :home, :pagestep ]
  PREFERENCE_KEYS.each { |key|
    define_method(key) {
      remote_call(:get_preference, key)
    }
  } if false
  def initialize(session)
    puts "BBMB::Html::Util::KnownUser.new object_id is #{self.object_id} SBSM::Session ? #{self.is_a? SBSM::Session} auth_session is #{session.class}"
    @auth_session = session.auth_session
    # puts "backtrace #{caller.join("\n")}"
    # @auth_session.auth.allowed?('edit', 'yus.entities')
  end
  def allowed?(action, key=nil)
    if @auth_session
      return @auth_session.allowed?(action, key)
      return @auth_session.remote_call(:allowed?, action, key)
    end
    SBSM.debug('User ' + sprintf('allowed?(%s, %s)', action, key))
    if defined?(yus_user) && yus_user
      allowed = yus_user.send(:allowed?, action, key)
    end if false
    return true
    # SBSM.debug('User'+ sprintf('allowed?(%s, %s) -> %s', action, key, allowed))
    return allowed
    # session.rb:25:in `login' BBMB::Html::Util::Session login claude.meier@gmx.net 5972659ce6c7f9b2356c0e650c7c40a3
    allowed = remote_call(:allowed?, action, key)
    SBSM.debug('User') {
      sprintf('%s: allowed?(%s, %s) -> %s', name, action, key, allowed)
    }
    allowed
  rescue => error
    puts error
    puts error.backtrace.join("\n")
  end
  def entity_valid?(email)
    !!(@auth_session.allowed?('edit', 'yus.entities') \
      && (entity = @auth_session.find_entity(email)) && entity.valid?)
  end
  def navigation
    puts "BBMB::Html::Util::KnownUser navigation returning  [ :logout ]"
    [ :logout ]
  end
  def get_preference(key)
    return @auth_session.get_preference(key.to_s)
    remote_call(:get_preference, key)
  end
  def remote_call(method, *args, &block)
    SBSM.debug("remote_call #{method} args #{args} block.nil? #{block.nil?}")
    if defined?(@auth_session) && @auth_session.is_a?(DRb::DRbObject)
      return @auth_session.send(method, *args, &block)
    else
      return false
      return super(method, *args, &block)
    end
  rescue RangeError, DRb::DRbError => e
    SBSM.info('auth') { e }
  rescue error
    puts error
    puts error.backtrace.join("\n")
  end
  # alias :method_missing :remote_call
end
    end
  end
end
