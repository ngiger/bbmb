#!/usr/bin/env ruby
# encoding: utf-8
$: << File.expand_path('..', File.dirname(__FILE__))

require 'test_helper'

require 'bbmb/model/customer'
require 'bbmb/model/order'

module BBMB
  module Model
class TestCustomer < Minitest::Test
  include FlexMock::TestCase
  def setup
    super
    BBMB.config = $default_config.clone
    Customer.clear_instances
    @customer = Customer.new('007')
  end
  def teardown
    BBMB.config = $default_config.clone
    super
  end

  def test_email_writer
    BBMB.server = flexmock('server')
    @customer.instance_variable_set('@email', 'old@bbmb.ch')
    BBMB.server.should_receive(:rename_user).once
    @customer.email = 'test@bbmb.ch'
    assert_equal('test@bbmb.ch', @customer.email)
  end
  def test_email_writer__nil
    BBMB.server = flexmock('server')
    @customer.instance_variable_set('@email', 'old@bbmb.ch')
    assert_raises(RuntimeError) {
      @customer.email = nil
    }
    assert_equal('old@bbmb.ch', @customer.email)
  end
  def test_email_writer__both_nil
    BBMB.server = flexmock('server')
    @customer.email = nil
    assert_nil(@customer.email)
  end
  def test_protect
    assert_equal false, @customer.protects?(:email)
    @customer.protect!(:email)
    assert_equal true, @customer.protects?(:email)
  end
  def test_current_order
    assert_instance_of(Model::Order, @customer.current_order)
  end
  def test_commit_order
    assert_equal(true, @customer.current_order.empty?)
  end
  def test_inject_order__empty
    assert_raises(RuntimeError) {
      @customer.inject_order(Model::Order.new(@customer))
    }
    assert_equal({}, @customer.archive)
  end
  def test_inject_order
    order = flexmock(Model::Order.new(@customer))
    time = Time.now
    order.should_receive(:commit!).with(1, time).times(1)
    @customer.inject_order(order, time)
    assert_equal({1 => order}, @customer.archive)
  end
end
  end
end
