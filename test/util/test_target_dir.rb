#!/usr/bin/env ruby
# encoding: utf-8
$: << File.expand_path('..', File.dirname(__FILE__))

require 'test_helper'
require 'fileutils'
require 'bbmb/util/target_dir'

module BBMB
  module Util
class TestTargetDir < Minitest::Test
  include FlexMock::TestCase
  def setup
    super
    BBMB.config = config = flexmock('config')
    bbmb_dir = File.expand_path('..', File.dirname(__FILE__))
    config.should_receive(:bbmb_dir).and_return(bbmb_dir)
    @dir = File.expand_path('../data/destination',
                            File.dirname(__FILE__))
  end
  def teardown
    BBMB.config = $default_config.clone
    FileUtils.rm_r(@dir) if(File.exist? @dir)
    super
  end
  def test_send_order__ftp
    config = BBMB.config
    FileUtils.mkdir_p(@dir)
    ftp = "ftp://user:pass@test.host.com#{@dir}"
    config.should_receive(:order_destinations).and_return([ftp])
    config.should_receive(:tmpfile_basename).and_return('bbmb')
    order = flexmock('order')
    order.should_receive(:order_id).and_return('order_id')
    order.should_receive(:to_target_format).and_return('data')
    order.should_receive(:filename).and_return('order.csv')
    flexstub(Net::FTP).should_receive(:open)\
      .and_return { |host, user, pass, block|
      assert_equal('test.host.com', host)
      assert_equal('user', user)
      assert_equal('pass', pass)
      fsession = flexmock('ftp')
      fsession.should_receive(:put).and_return { |local, remote|
        assert_equal(File.join(@dir, 'order.csv').sub(/^\//, ''), remote)
      }
      block.call(fsession)
    }
    TargetDir.send_order(order)
  end
  def test_send_order__local
    config = BBMB.config
    FileUtils.mkdir_p(@dir)
    config.should_receive(:order_destinations).and_return([@dir])
    config.should_receive(:tmpfile_basename).and_return('bbmb')
    order = flexmock('order')
    order.should_receive(:order_id).and_return('order_id')
    order.should_receive(:to_target_format).and_return('data')
    order.should_receive(:filename).and_return('order.csv')
    flexstub(Net::FTP).should_receive(:open).times(0)

    TargetDir.send_order(order)
    path = File.join(@dir, 'order.csv')
    assert File.exists?(path)
    assert_equal("data\n", File.read(path))
  end
  def test_send_order__local__relative
    FileUtils.mkdir_p(@dir)
    config = BBMB.config
    config.should_receive(:order_destinations).and_return(['data/destination'])
    config.should_receive(:tmpfile_basename).and_return('bbmb')
    order = flexmock('order')
    order.should_receive(:order_id).and_return('order_id')
    order.should_receive(:to_target_format).and_return('data')
    order.should_receive(:filename).and_return('order.csv')
    flexstub(Net::FTP).should_receive(:open).times(0)

    TargetDir.send_order(order)
    path = File.join(@dir, 'order.csv')
    assert File.exists?(path)
    assert_equal("data\n", File.read(path))
  end
end
  end
end
