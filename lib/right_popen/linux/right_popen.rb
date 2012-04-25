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
      rescue Errno::EBADF, EOFError, IOError
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

  # Forks process to run given command asynchronously, hooking all three
  # standard streams of the child process.
  #
  # === Parameters
  # options[:pid_handler](Symbol):: Token for pid handler method name.
  #
  # See RightScale.popen3
  def self.popen3_imp(options)
    GC.start # To garbage collect open file descriptors from past executions
    EM.next_tick do
      process = RightPopen::Process.new(:environment => options[:environment] || {})
      process.fork(options[:command])

      handlers = []
      handlers << EM.attach(process.status_fd, StatusHandler, process.status_fd)
      handlers << EM.attach(process.stderr, PipeHandler, process.stderr, options[:target],
                            options[:stderr_handler])
      handlers << EM.attach(process.stdout, PipeHandler, process.stdout, options[:target],
                            options[:stdout_handler])
      handlers << EM.attach(process.stdin, InputHandler, process.stdin, options[:input])

      options[:target].method(options[:pid_handler]).call(process.pid) if options.key? :pid_handler

      handle_exit(process.pid, 0.1, handlers, options)
    end
    true
  end

  # Wait for process to exit and then call exit handler
  # If no exit detected, double the wait time up to a maximum of 2 seconds
  #
  # === Parameters
  # pid(Integer):: Process identifier
  # wait_time(Fixnum):: Amount of time to wait before checking status
  # handlers(Array):: Handlers for status, stderr, stdout, and stdin
  # options[:exit_handler](Symbol):: Handler to be called when process exits
  # options[:target](Object):: Object initiating command execution
  #
  # === Return
  # true:: Always return true
  def self.handle_exit(pid, wait_time, handlers, options)
    EM::Timer.new(wait_time) do
      if value = Process.waitpid2(pid, Process::WNOHANG)
        ignored, status = value
        first_exception = nil
        handlers.each do |h|
          begin
            h.drain_and_close
          rescue Exception => e
            first_exception = e unless first_exception
          end
        end
        options[:target].method(options[:exit_handler]).call(status) if options[:exit_handler]
        raise first_exception if first_exception
      else
        handle_exit(pid, [wait_time * 2, 1].min, handlers, options)
      end
    end
    true
  end
end
