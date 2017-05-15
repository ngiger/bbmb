#!/usr/bin/env ruby
# encoding: utf-8

require 'uri'
require 'bbmb/config'
require 'sbsm/session'
require 'bbmb/html/state/global'
require 'bbmb/html/util/known_user'


module BBMB
  module Html
    module Util
class Session < SBSM::Session
  DEFAULT_LANGUAGE = 'de'
  DEFAULT_FLAVOR = 'bbmb'
  DEFAULT_STATE = State::Login
  EXPIRES = BBMB.config.session_timeout
  PERSISTENT_COOKIE_NAME = "bbmb-barcodereader"
  if uri = URI.parse(BBMB.config.http_server)
    SERVER_NAME = uri.host
  end
  attr_reader :email, :pass, :auth_session
  def initializexx(app:,  cookie_name:, trans_handler:, validator:)
    super(app,  cookie_name, trans_handler, validator)
  end
  def login
    @email = user_input(:email)
    @password = user_input(:pass)
    # @user.respond_to?(:session=)) is FALSE!!!!
    @user.session = self if(@user.respond_to?(:session=))
    # Before rack: @user = @app.login(user_input(:email), user_input(:pass))
    @auth = DRb::DRbObject.new(nil, BBMB.config.auth_url)
    @auth_session = @auth.login(user_input(:email), user_input(:pass), BBMB.config.auth_domain) # logs in claude meier without problem, but not admin
    if @auth_session.valid?
      @user = BBMB::Html::Util::KnownUser.new(self) # TODO:Should we set it already in the initialize method?
    else
      @user = SBSM::UnknownUser
    end
    SBSM.info "BBMB::Html::Util::Session login #{user_input(:email)} #{user_input(:pass)}  #{@user.class} @auth #{@auth} auth_session #{@auth_session}"
    pp @auth
    pp @auth_session
    pp @user
    @user
  end
  def logout
    SBSM.info "BBMB::Html::Util::Session logout @auth_session #{@auth_session.class}"
    $stdout.sync = true
    @app.logout(@user.auth_session) if(@user.respond_to?(:auth_session))
    super
  end

  def lookandfeel
    if(@lookandfeel.nil? \
      || (@lookandfeel.language != persistent_user_input(:language)))
      require 'bbmb/html/util/lookandfeel'
      @lookandfeel = Lookandfeel.new(self)
    end
    @lookandfeel
  end
  def process(request)
    SBSM.info "BBMB::Html::Util::Session process"
    begin
      if(@user.is_a?(KnownUser) && @user.auth_session.expired?)
        logout
      end
    rescue DRb::DRbError, RangeError, NoMethodError
      logout
    end
    super
  end
  def validate(key, value)
    @validator.validate(key, value)
  end
  def remote_call(method, *args, &block)
    @yus_user.send(method, *args, &block)
  rescue RangeError, DRb::DRbError => e
    BBMB.logger.error('auth') { e }
  end
end
    end
  end
end
