#--
# Copyright (c) 2009 RightScale Inc
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

# RightScale.popen3 allows running external processes aynchronously
# while still capturing their standard and error outputs.
# It relies on EventMachine for most of its internal mechanisms.

require 'rubygems'
require 'eventmachine'
require File.expand_path(File.join(File.dirname(__FILE__), "process"))
require File.expand_path(File.join(File.dirname(__FILE__), "accumulator"))
require File.expand_path(File.join(File.dirname(__FILE__), "utilities"))

module RightScale
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
      rescue Errno::EBADF
      rescue EOFError
      end
      close_connection
    end

    def unbind
      if @data.size > 0
        e = Marshal.load @data
        raise (Exception === e ? e : "unknown failure: saw #{e} on status channel")
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
      @handler = handler
    end

    def receive_data(data)
      @target.method(@handler).call(data) if @handler
    end

    def drain_and_close
      begin
        while ready = IO.select([@handle], nil, nil, 0)
          break if @handle.eof?
          data = @handle.readpartial(4096)
          receive_data(data)
        end
      rescue Errno::EBADF
      rescue EOFError
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

  # Forks process to run given command asynchronously, hooking all three
  # standard streams of the child process.
  #
  # === Parameters
  # options[:pid_handler](Symbol):: Token for pid handler method name.
  #
  # See RightScale.popen3
  def self.popen3_imp(options)
    GC.start # To garbage collect open file descriptors from passed executions
    EM.next_tick do
      process = RightPopen::Process.new(:environment => options[:environment] || {})
      process.fork(options[:command])

      status_handler = EM.attach(process.status_fd, StatusHandler, process.status_fd)
      stderr_handler = EM.attach(process.stderr, PipeHandler, process.stderr, options[:target],
                                 options[:stderr_handler])
      stdout_handler = EM.attach(process.stdout, PipeHandler, process.stdout, options[:target],
                                 options[:stdout_handler])
      stdin_handler = EM.attach(process.stdin, InputHandler, process.stdin, options[:input])

      options[:target].method(options[:pid_handler]).call(process.pid) if
        options.key? :pid_handler

      wait_timer = EM::PeriodicTimer.new(1) do
        value = ::Process.waitpid2(process.pid, Process::WNOHANG)
        unless value.nil?
          begin
            ignored, status = value
            options[:target].method(options[:exit_handler]).call(status) if
              options[:exit_handler]
          ensure
            stdin_handler.drain_and_close
            stdout_handler.drain_and_close
            stderr_handler.drain_and_close
            status_handler.drain_and_close
            wait_timer.cancel
          end
        end
      end
    end
    return process.pid
  end
end
