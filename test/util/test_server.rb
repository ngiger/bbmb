#!/usr/bin/env ruby
# encoding: utf-8
$: << File.expand_path('..', File.dirname(__FILE__))
require 'test_helper'
require 'sbsm/logger'
require 'bbmb/util/rack_interface'
require 'bbmb/util/app'

module BBMB
  module Util

class TestServer < Minitest::Test
  CUSTOMER_ID = '12345'
  CUSTOMER_EAN13 = '0987654321098'
  COMMENT = 'My Comment'
  REFERENCE = 'reference 76543'

  def setup
    require 'bbmb/util/server'
    super
    BBMB.config = $default_config.clone
    @rack_app = BBMB::Util::App.new
    @server = BBMB::Util::Server.new('none', @rack_app)
    Model::Customer.instances.clear
    Model::Product.instances.clear
  end
  def teardown
    BBMB.config = $default_config.clone
    super
  end
  def test_inject_order__unknown_customer
    assert_raises(RuntimeError) {
      @server.inject_order(CUSTOMER_ID, [], {})
    }
  end
  def test_inject_order
    pr1 = Model::Product.new 1
    pr1.pcode = '1234567'
    pr2 = Model::Product.new 2
    pr2.ean13 = '1234567890123'
    pr3 = Model::Product.new 3
    pr3.ean13 = '2345678901234'
    pr3.pcode = '2345678'
    customer = Model::Customer.new(CUSTOMER_ID)
    prods = [
      {:quantity => 3, :pcode => '1234567'},
      {:quantity => 4, :ean13 => '1234567890123'},
      {:quantity => 5, :pcode => '2345678', :ean13 => '2345678901234'},
    ]
    infos = {
      :comment => COMMENT,
      :reference => REFERENCE,
    }
    customer_mock = flexmock("find_by_customer_id",  Model::Customer)
    customer_mock.should_receive(:find_by_customer_id).with(CUSTOMER_ID).and_return(customer).once
    result = @server.inject_order(CUSTOMER_ID, prods, infos)
    assert_equal("#{CUSTOMER_ID}-1", result[:order_id])
    assert_equal(3, result[:products].size)
    assert_equal(COMMENT, customer.archive.values.first.comment)
    assert_equal(REFERENCE, customer.archive.values.first.reference)
  end
  def test_inject_order__customer_by_ean13
    pr1 = Model::Product.new 1
    pr1.pcode = '1234567'
    pr2 = Model::Product.new 2
    pr2.ean13 = '1234567890123'
    pr3 = Model::Product.new 3
    pr3.ean13 = '2345678901234'
    pr3.pcode = '2345678'
    customer = Model::Customer.new(CUSTOMER_ID)
    customer.ean13 = CUSTOMER_EAN13
    prods = [
      {:quantity => 3, :pcode => '1234567'},
      {:quantity => 4, :ean13 => '1234567890123'},
      {:quantity => 5, :pcode => '2345678', :ean13 => '2345678901234'},
    ]
    infos = {
      :comment => COMMENT,
      :reference => REFERENCE,
    }
    flexmock(BBMB::Util::Mail).should_receive(:send_order).with(BBMB::Model::Order)
    BBMB.config.mail_confirm_reply_to = 'replyto@test.org'
    BBMB.config.error_recipients = 'to@test.org'
    customer_mock = flexmock("find_by_customer_id",  Model::Customer)
    customer_mock.should_receive(:find_by_customer_id).with(CUSTOMER_EAN13).and_return(customer).once
    result = @server.inject_order(CUSTOMER_EAN13, prods, infos, :deliver => true)
    assert_equal("#{CUSTOMER_ID}-1", result[:order_id])
    assert_equal(3, result[:products].size)
    assert_equal(3, result[:products][0][:quantity])
    assert_equal(4, result[:products][1][:quantity])
    assert_equal(5, result[:products][2][:quantity])
    assert_equal(false, result[:products][0][:backorder])
    assert_nil(result[:products][1][:backorder])
    assert_equal(false, result[:products][2][:backorder])
    assert_equal('pharmacode 2345678', result[:products][2][:description])
    assert_equal(1, customer.archive.size)
    assert_equal(1, customer.archive.keys.first)
    assert_equal(CUSTOMER_ID, customer.customer_id)
    assert_equal(COMMENT, customer.archive.values.first.comment)
    assert_equal(REFERENCE, customer.archive.values.first.reference)
  end
  def test_rename_user__new
    BBMB.config = flexmock('config')
    BBMB.config.should_receive(:auth_domain).times(1).and_return('ch.bbmb')
    BBMB.auth = flexmock('auth')
    session = flexmock('yus-session')
    BBMB.auth.should_receive(:autosession).times(1).and_return { |domain, block|
      assert_equal('ch.bbmb', domain)
      block.call(session)
    }
    session.should_receive(:create_entity).times(1).and_return { |email|
      assert_equal('test@bbmb.ch', email)
    }
    @server.rename_user('cutomer_id', nil, 'test@bbmb.ch')
  end
  def test_rename_user__existing
    BBMB.config = flexmock('config')
    BBMB.config.should_receive(:auth_domain).times(1).and_return('ch.bbmb')
    BBMB.auth = flexmock('auth')
    session = flexmock('yus-session')
    BBMB.auth.should_receive(:autosession).times(1).and_return { |domain, block|
      assert_equal('ch.bbmb', domain)
      block.call(session)
    }
    session.should_receive(:rename).times(1).and_return { |previous, email|
      assert_equal('old@bbmb.ch', previous)
      assert_equal('test@bbmb.ch', email)
    }
    @server.rename_user('cutomer_id',   'old@bbmb.ch', 'test@bbmb.ch')
  end
  def test_rename_user__same
    @server.rename_user('cutomer_id', 'test@bbmb.ch', 'test@bbmb.ch')
  end
  def test_run_invoicer
    error_mock = flexmock(RuntimeError.new, 'error')
    flexstub(Mail).should_receive(:notify_error).at_least.once.and_return { |error|
      assert_instance_of(RuntimeError, error_mock)
    }
    flexstub(Invoicer).should_receive(:run).times(1).and_return { |range|
      assert_instance_of(Range, range)
      raise "notify an error!"
    }
    invoicer = @server.run_invoicer
    Timeout.timeout(5) {
      until(invoicer.status == 'sleep')
        sleep 0.1
      end
    }
    invoicer.wakeup
    assert_equal('run', invoicer.status)
    until(invoicer.status == 'sleep')
      sleep 0.1
    end
    invoicer.exit
  end
  def test_run_updater
    BBMB.config = flexmock('config')
    BBMB.config.should_receive(:update_hour).and_return(0)
    flexstub(Mail).should_receive(:notify_error).times(1).and_return { |error|
      assert_instance_of(RuntimeError, error)
    }
    flexstub(Updater).should_receive(:run).times(1).and_return {
      raise "notify an error!"
    }
    updater = @server.run_updater
    Timeout.timeout(5) {
      until(updater.status == 'sleep')
        sleep 0.1
      end
    }
    updater.wakeup
    assert_equal('run', updater.status)
    until(updater.status == 'sleep')
      sleep 0.1
    end
    updater.exit
  end
end
  end
end
