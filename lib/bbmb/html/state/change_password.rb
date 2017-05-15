#!/usr/bin/env ruby
# Html::State::ChangePassword -- virbac.bbmb.ch -- 28.06.2007 -- hwyss@ywesee.com

require 'bbmb/html/state/global'
require 'bbmb/html/view/change_password'

module BBMB
  module Html
    module State
class ChangePassword < Global
  DIRECT_EVENT = :change_pass
  VIEW = Html::View::ChangePassword
  mandatory :email, :pass, :confirm_pass
  def save
    keys = mandatory
    input = user_input(keys, keys)
    if(error?)
      @errors.dup.each { |key, val|
        if(/^e_(empty|missing)_/.match val.message)
          @errors.store(key, create_error(:e_need_all_fields, key, nil))
        end
      }
    else
      update_user input
      unless(error?)
        BBMB.persistence.save(@model)
        return State::Info.new(@session, :message => :login_data_saved,
                                         :event => :home)
      end
    end
    self
  end
  def update_user(input)
    email = input.delete(:email)
    @model.email = email
    @model.protect!(:email)
    if(passhash = input.delete(:confirm_pass))
      begin
        @session.auth_session.set_password(email, passhash)
      rescue Yus::YusError => e
        @errors.store(:pass, create_error(:e_pass_not_set, :email, email))
      end
    end
  rescue Yus::YusError => e
    @errors.store(:email, create_error(:e_duplicate_email, :email, email))
  end
end
    end
  end
end
