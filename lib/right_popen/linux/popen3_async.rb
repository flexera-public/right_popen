#--
# Copyright (c) 2009-2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'rubygems'
require 'eventmachine'

require File.expand_path(File.join(File.dirname(__FILE__), "process"))

module RightScale::RightPopen

  # ensure uniqueness of handler to avoid confusion.
  raise "#{StatusHandler.name} is already defined" if defined?(StatusHandler)

  module StatusHandler
    def initialize(file_handle)
      # Voodoo to make sure that Ruby doesn't gc the file handle
      # (closing the stream) before we're done with it.  No, oddly
      # enough EventMachine is not good about holding on to this
      # itself.
      @handle = file_handle
      @data = ""
    end

    def receive_data(data)
      @data << data
    end

    def drain_and_close
      begin
        while ready = IO.select([@handle], nil, nil, 0)
          break if @handle.eof?
          data = @handle.readpartial(4096)
          receive_data(data)
        end
      rescue Errno::EBADF, EOFError, IOError
      end
      close_connection
    end

    def unbind
      if @data.size > 0
        e = ::Marshal.load(@data)
        raise (::Exception === e ? e : "unknown failure: saw #{e} on status channel")
      end
    end
  end
  
  # ensure uniqueness of handler to avoid confusion.
  raise "#{PipeHandler.name} is already defined" if defined?(PipeHandler)

  module PipeHandler
    def initialize(file_handle, target, handler)
      # Voodoo to make sure that Ruby doesn't gc the file handle
      # (closing the stream) before we're done with it.  No, oddly
      # enough EventMachine is not good about holding on to this
      # itself.
      @handle = file_handle
      @target = target
      @data_handler = @target.method(handler)
    end

    def receive_data(data)
      @data_handler.call(data)
    end

    def drain_and_close
      begin
        while ready = IO.select([@handle], nil, nil, 0)
          break if @handle.eof?
          data = @handle.readpartial(4096)
          receive_data(data)
        end
      rescue Errno::EBADF, EOFError, IOError
      end
      close_connection
    end
  end

  # ensure uniqueness of handler to avoid confusion.
  raise "#{InputHandler.name} is already defined" if defined?(InputHandler)

  module InputHandler
    def initialize(file_handle, string)
      # Voodoo to make sure that Ruby doesn't gc the file handle
      # (closing the stream) before we're done with it.  No, oddly
      # enough EventMachine is not good about holding on to this
      # itself.
      @handle = file_handle
      @string = string
    end

    def post_init
      send_data(@string) if @string
      close_connection_after_writing
    end

    def drain_and_close
      close_connection
    end
  end

  # See RightScale.popen3_async for details
  def self.popen3_async_impl(cmd, target, options)
    # always create eventables on the main EM thread by using next_tick. this
    # prevents synchronization problems between EM threads.
    ::EM.next_tick do
      # create process.
      process = ::RightScale::RightPopen::Process.new(options)
      process.spawn(cmd, target)

      # connect EM eventables to open streams.
      handlers = []
      handlers << ::EM.attach(process.status_fd, ::RightScale::RightPopen::StatusHandler, process.status_fd)
      handlers << ::EM.attach(process.stderr, ::RightScale::RightPopen::PipeHandler, process.stderr, target, :stderr_handler)
      handlers << ::EM.attach(process.stdout, ::RightScale::RightPopen::PipeHandler, process.stdout, target, :stdout_handler)
      handlers << ::EM.attach(process.stdin, ::RightScale::RightPopen::InputHandler, process.stdin, options[:input])

      target.pid_handler(process.pid)

      # initial watch callback.
      #
      # note that we cannot abandon async watch; callback needs to interrupt
      # in this case
      target.watch_handler(process)

      # periodic watcher.
      watch_process(process, 0.1, target, handlers)
    end
    true
  end

  # watches process for exit or interrupt criteria. doubles the wait time up to
  # a maximum of 1 second for next wait.
  #
  # === Parameters
  # @param [Process] process that was run
  # @param [Numeric] wait_time as seconds to wait before checking status
  # @param [Object] target for handler calls
  # @param [Array] handlers used by eventmachine for status, stderr, stdout, and stdin
  #
  # === Return
  # true:: Always return true
  def self.watch_process(process, wait_time, target, handlers)
    ::EM::Timer.new(wait_time) do
      if process.alive?
        if process.timer_expired? || process.size_limit_exceeded?
          process.interrupt
        else
          # cannot abandon async watch; callback needs to interrupt in this case
          target.watch_handler(process)
        end
        watch_process(process, [wait_time * 2, 1].min, target, handlers)
      else
        first_exception = nil
        handlers.each do |h|
          begin
            h.drain_and_close
          rescue ::Exception => e
            first_exception = e unless first_exception
          end
        end
        process.wait_for_exit_status
        target.timeout_handler if process.timer_expired?
        target.size_limit_handler if process.size_limit_exceeded?
        target.exit_handler(process.status)
        raise first_exception if first_exception
      end
    end
    true
  end
end
