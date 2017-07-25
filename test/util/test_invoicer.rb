#!/usr/bin/env ruby
# encoding: utf-8
$: << File.expand_path('..', File.dirname(__FILE__))

require 'test_helper'
require 'ostruct'
require 'bbmb/config'
require 'bbmb/util/invoicer'
require 'bbmb/util/numbers'

module BBMB
  module Util
class TestInvoicer < Minitest::Test
  def setup
    @drb_server.stop_service if @drb_server
    super
    BBMB.config = $default_config.clone
    ::Mail.defaults do  delivery_method :test end
    key = OpenSSL::PKey::DSA.new(512)
    keypath = File.expand_path('../data/private_key', File.dirname(__FILE__))
    File.open(keypath, 'w') { |fh| fh.puts(key) }
    YDIM::Client::CONFIG.private_key = keypath
    BBMB.config = flexmock($default_config.clone, 'config')
    @session = flexmock('session')
    @ydim_server = flexmock('ydim')
    @ydim_server.should_receive(:login).and_return(@session)
    @drb_server = false
    @ydim_url = 'druby://localhost:10082'
    @ydim_config = flexmock(YDIM::Client::CONFIG, 'ydim_config')
    @ydim_config.should_receive(:server_url).and_return(@ydim_url)
  end

  def teardown
    @drb_server.stop_service if @drb_server
    BBMB.config = $default_config.clone
    super
  end
  def test_create_invoice
    datadir = File.expand_path('data', File.dirname(__FILE__))
    order1 = flexmock('order1')
    order2 = flexmock('order2')
    order1.should_receive(:total).and_return(Util::Money.new(11.00))
    order2.should_receive(:total).and_return(Util::Money.new(13.00))
    path = File.join(datadir, "ydim.yml")
    FileUtils.mkdir_p(datadir)
    File.open(path, 'w') { |fh|
      fh.puts({'server_url' => @ydim_url}.to_yaml) }
    @ydim_config.should_receive(:load).and_return { |ydim_path|
      assert_equal(path, ydim_path)
    }
    BBMB.config.should_receive(:ydim_config).and_return(path)
    BBMB.config.should_receive(:ydim_id).and_return(7)
    BBMB.config.should_receive(:invoice_percentage).and_return(1)
    BBMB.config.should_receive(:invoice_format).and_return("%s - %s")
    BBMB.config.should_receive(:invoice_item_format).and_return("%1.2f -> %i")
    BBMB.config.should_receive(:invoice_monthly_baseline)
    BBMB.config.should_receive(:invoice_monthly_baseamount)
    session = flexmock('session')
    @ydim_server = flexmock('ydim')
    @ydim_server.should_receive(:login).and_return(session)
    invoice = OpenStruct.new
    invoice.unique_id = 2
    session.should_receive(:create_invoice).with(7).and_return(invoice).once
    today = Date.new(2006,10)
    data = {
      :price    => 0.24,
      :quantity => 1,
      :text     => "24.00 -> 2",
      :time     => Time.local(2006,10),
      :unit     => "1.0%",
    }
    session.should_receive(:add_items).with(2, [data]).once
    @ydim_server.should_receive(:logout).with(session)
    range = Time.local(2006,9)..Time.local(2006,10)
    @drb_server = DRb.start_service(@ydim_url, @ydim_server)
    sleep 0.5
    result = Invoicer.create_invoice(range, Util::Money.new(24), [order1, order2], today)
    assert_equal(invoice, result)
    assert_equal("01.09.2006 - 30.09.2006", invoice.description)
    assert_equal(today, invoice.date)
    assert_equal('CHF', invoice.currency)
    assert_equal(30, invoice.payment_period)
  ensure
    FileUtils.rm_r(datadir) if(File.exist?(datadir))
    @drb_server.stop_service
  end
  def test_send_invoice
    session = flexmock('session')
    session.should_receive(:send_invoice).with(123)
    @ydim_server = flexmock('ydim')
    @ydim_server.should_receive(:login).and_return(session)
    @ydim_server.should_receive(:logout)
    @drb_server = DRb.start_service(@ydim_url, @ydim_server)
    Invoicer.send_invoice(123)
  end
  def test_run
    order1 = flexmock('order1')
    order1.should_receive(:total).and_return(Util::Money.new(11.00))
    order1.should_receive(:commit_time).and_return(Time.local(2006,8,31,23,59,59))
    order2 = flexmock('order2')
    order2.should_receive(:total).and_return(Util::Money.new(13.00))
    order2.should_receive(:commit_time).and_return(Time.local(2006,9))
    order3 = flexmock('order3')
    order3.should_receive(:total).and_return(Util::Money.new(17.00))
    order3.should_receive(:commit_time).and_return(Time.local(2006,9,30,23,59,59))
    order4 = flexmock('order4')
    order4.should_receive(:total).and_return(Util::Money.new(19.00))
    order4.should_receive(:commit_time).and_return(Time.local(2006,10))
    unless BBMB.persistence
      BBMB.persistence = flexmock('persistence')
      BBMB.persistence.should_receive(:all).and_return([])
    end
    BBMB.config.should_receive(:ydim_config)
    BBMB.config.should_receive(:ydim_id).and_return(7)
    BBMB.config.should_receive(:error_recipients).and_return(::TestRecipient)
    BBMB.config.should_receive(:invoice_percentage).and_return(1)
    BBMB.config.should_receive(:invoice_format).and_return("%s - %s")
    BBMB.config.should_receive(:invoice_item_format).and_return("%1.2f -> %i")
    BBMB.config.should_receive(:invoice_baseline).and_return(20)
    BBMB.config.should_receive(:invoice_newyear).and_return('1.1.')
    BBMB.config.should_receive(:invoice_monthly_baseline)
    BBMB.config.should_receive(:invoice_monthly_baseamount)
    today = Date.new(2006,10)
    data = {
      :price    => 0.21,
      :quantity => 1,
      :text     => "21.00 -> 2",
      :time     => Time.local(2006,10),
      :unit     => "1.0%",
    }
    @session.should_receive(:add_items)
    @ydim_server.should_receive(:logout)
    range = Time.local(2006,9)...Time.local(2006,10)
    @session.should_receive(:send_invoice).with(39)
    @drb_server = DRb.start_service(@ydim_url, @ydim_server)
    Invoicer.run(range, today)
    @drb_server.stop_service
  end
  def test_number_format
    assert_equal "155",  Invoicer.number_format('155')
    assert_equal "15.5", Invoicer.number_format('15.5')
    assert_equal '1.55', Invoicer.number_format('1.55')
    assert_equal "1'555", Invoicer.number_format('1555')
    assert_equal "155.5", Invoicer.number_format('155.5')
    assert_equal '15.55', Invoicer.number_format('15.55')
    assert_equal '1.555', Invoicer.number_format('1.555')
    assert_equal "15'555",  Invoicer.number_format('15555')
    assert_equal "1'555.5", Invoicer.number_format('1555.5')
    assert_equal '155.55',  Invoicer.number_format('155.55')
    assert_equal '15.555',  Invoicer.number_format('15.555')
    assert_equal '1.5555',  Invoicer.number_format('1.5555')
    assert_equal "155'555",  Invoicer.number_format('155555')
    assert_equal "15'555.5", Invoicer.number_format('15555.5')
    assert_equal "1'555.55", Invoicer.number_format('1555.55')
    assert_equal "155.555",  Invoicer.number_format('155.555')
    assert_equal "15.5555",  Invoicer.number_format('15.5555')
    assert_equal "1.55555",  Invoicer.number_format('1.55555')
    assert_equal "1'555'555", Invoicer.number_format('1555555')
    assert_equal "155'555.5", Invoicer.number_format('155555.5')
    assert_equal "15'555.55", Invoicer.number_format('15555.55')
    assert_equal "1'555.555", Invoicer.number_format('1555.555')
    assert_equal "155.5555",  Invoicer.number_format('155.5555')
    assert_equal "15.55555",  Invoicer.number_format('15.55555')
    assert_equal "1.555555",  Invoicer.number_format('1.555555')
  end
end
  end
end
