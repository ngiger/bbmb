#!/usr/bin/env ruby
# Util::PollingManager -- bbmb.ch -- 14.09.2006 -- hwyss@ywesee.com

require 'bbmb'
require 'bbmb/util/mail'
require 'fileutils'
require 'net/ftp'
require 'net/pop'
require 'tmpdir'
require 'uri'
require 'yaml'

module BBMB
  module Util
class FileMission
  attr_accessor :backup_dir, :delete, :directory, :glob_pattern
  def file_paths
    path = File.expand_path(@glob_pattern || '*', @directory)
    res = Dir.glob(path).collect { |entry|
      File.expand_path(entry, @directory)
    }.compact
    puts res
    res
  end
  def poll(&block)
    @directory = File.expand_path(@directory, BBMB.config.bbmb_dir) unless File.directory?(@directory) &&
        File.absolute_path(@directory) == @directory
    file_paths.each { |path|
      poll_path(path, &block)
    }
  end
  def poll_path(path, &block)
    File.open(path) { |io|
      block.call(File.basename(path), io)
    }
  rescue StandardError => err
    BBMB::Util::Mail.notify_error(err)
  ensure
    if(@backup_dir)
      if File.absolute_path(@backup_dir) == @backup_dir
        dir = @backup_dir
      else
        dir = File.expand_path(@backup_dir, BBMB.config.bbmb_dir)
      end
      FileUtils.mkdir_p(dir)
      FileUtils.cp(path, dir)
    end
    if(@delete)
      FileUtils.rm(path)
    end
  end
end
class PopMission
  attr_accessor :host, :port, :user, :pass, :content_type
  def poll(&block)
    # puts "PopMission starts polling host #{@host}:#{@port} u: #{@user} pw: #{@pass}"
    options = {
                      :address    => @host,
                      :port       => @port,
                      :user_name  => @user,
                      :password   => @pass,
                      :enable_ssl => true
      }
    ::Mail.defaults do retriever_method :pop3, options  end
    all_mails = ::Mail.delivery_method.is_a?(::Mail::TestMailer) ? ::Mail::TestMailer.deliveries : ::Mail.all
    all_mails.each do |mail|
        begin
          poll_message(mail, &block)
        ensure
          time = Time.now
          name = sprintf("%s.%s.%s", @user, time.strftime("%Y%m%d%H%M%S"), time.usec)
          FileUtils.mkdir_p(@backup_dir)
          path = File.join(@backup_dir, name)
          File.open(path, 'w') { |fh| fh.puts(mail) }
          mail.mark_for_delete = true
          # mail.delete # Not necessary with gem mail, as delete_after_find is set to true by default
        end
    end
  end
  def poll_message(message, &block)
    if(message.multipart?)
      message.parts.each do |part|
        poll_message(part, &block)
      end
    elsif(/text\/xml/.match(message.content_type))
      filtered_transaction(message.decoded, sprintf('pop3:%s@%s:%s', @user, @host, @port), &block)
    end
  end
end
class FtpMission
  attr_accessor :backup_dir, :delete, :pattern, :directory
  def initialize(*args)
    super
    @regexp = Regexp.new('.*')
  end
  def poll(&block)
    @backup_dir ||= Dir.tmpdir
    FileUtils.mkdir_p(@backup_dir)
    @regexp = Regexp.new(@pattern || '.*')
    uri = URI.parse(@directory)
    locals = []
    Net::FTP.open(uri.host) do |ftp|
      ftp.login uri.user, uri.password
      ftp.chdir uri.path
      ftp.nlst.each do |file|
        if(local = poll_remote ftp, file)
          locals.push local
        end
      end
    end
    locals.each do |path|
      poll_file path, &block
    end
  end
  def poll_file(path, &block)
    File.open(path) { |io|
      block.call(File.basename(path), io)
    }
  rescue StandardError => err
    BBMB::Util::Mail.notify_error(err)
  end
  def poll_remote(ftp, file)
    if(@regexp.match file)
      local = File.join(@backup_dir, file)
      ftp.get file, local
      ftp.delete file if @delete
      local
    end
  end
  def regexp
  end
end
class PollingManager
  def load_sources(&block)
    file = File.open(BBMB.config.polling_file)
    YAML.load_documents(file) { |mission|
      block.call(mission)
    }
  ensure
    file.close if(file)
  end
  def poll_sources(&block)
    load_sources { |source|
      source.poll(&block)
    }
  end
end
  end
end
