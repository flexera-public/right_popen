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
require 'right_popen'

module RightScale::RightPopen

  # ensure uniqueness of handler to avoid confusion.
  raise "#{StdInHandler.name} is already defined" if defined?(StdInHandler)

  # Eventmachine callback handler for stdin stream
  module StdInHandler

    # === Parameters
    # options[:input](String):: Input to be streamed into child process stdin
    # stream_in(IO):: Standard input stream.
    def initialize(options, stream_in)
      @stream_in = stream_in
      @input = options[:input]
    end

    # Eventmachine callback asking for more to write
    # Send input and close stream in
    def post_init
      if @input
        send_data(@input)
        close_connection_after_writing
        @input = nil
      else
        close_connection
      end
    end

  end

  # ensure uniqueness of handler to avoid confusion.
  raise "#{StdOutHandler.name} is already defined" if defined?(StdOutHandler)

  # Provides an eventmachine callback handler for the stdout stream.
  module StdOutHandler

    # === Parameters
    # @param [Process] process that was executed
    # @param [Object] target defining handler methods to be called
    # @param [Connector] stderr_eventable EM object representing stderr handler.
    # @param [IO] stream_out as standard output stream
    def initialize(process, target, stderr_eventable, stream_out)
      @process = process
      @target = target
      @stderr_eventable = stderr_eventable
      @stream_out = stream_out
      @status = nil
    end

    # Callback from EM to asynchronously read the stdout stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8 but the win32 EM code
    # has never advanced beyond that point.
    def notify_readable
      data = @process.async_read(@stream_out)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @target.stdout_handler(data)
    end

    # Override of Connection.get_status() for Windows implementation.
    def get_status
      unless @status
        @status = @process.wait_for_exit_status
      end
      return @status
    end

    # Callback from EM to unbind.
    def unbind
      @stream_out.close

      # need a handshake for when both stdout and stderr are unbound.
      if @stderr_eventable
        @stderr_eventable.finish_unbind(self)
      else
        finish_unbind
      end
    end

    # Finishes unbind for stdout and stderr when both receive unbind.
    def finish_unbind
      @target.timeout_handler if @process.timer_expired?
      @target.size_limit_handler if @process.size_limit_exceeded?
      @target.exit_handler(get_status)
    end
  end

  # ensure uniqueness of handler to avoid confusion.
  raise "#{StdErrHandler.name} is already defined" if defined?(StdErrHandler)

  # Provides an eventmachine callback handler for the stderr stream.
  module StdErrHandler

    # === Parameters
    # @param [Process] process that was executed
    # @param [Object] target defining handler methods to be called
    # @param [IO] stream_err as standard error stream
    def initialize(process, target, stream_err)
      @process = process
      @target = target
      @stderr_handler = target.method(:stderr_handler)
      @stream_err = stream_err
      @stdout_eventable = nil
      @unbound = false
    end

    # Callback from EM to asynchronously read the stderr stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8 for Linux but not for
    # Windows.
    def notify_readable
      data = @process.async_read(@stream_err)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @stderr_handler.call(data)
    end

    # Callback from EM to unbind.
    def unbind
      @unbound = true
      @stream_err.close

      # handshake.
      @stdout_eventable.finish_unbind if @stdout_eventable
    end

    # Finishes unbind for stdout and stderr when both receive unbind.
    def finish_unbind(stdout_eventable)
      if @unbound
        stdout_eventable.finish_unbind
      else
        @stdout_eventable = stdout_eventable
      end
    end
  end

  # See RightScale.popen3_async for details
  def self.popen3_async_impl(cmd, target, options)
    # always create eventables on the main EM thread by using next_tick. this
    # prevents synchronization problems between EM threads.
    ::EM.next_tick do
      process = nil
      begin
        # create process.
        process = ::RightScale::RightPopen::Process.new(options)
        process.spawn(cmd, target)

        # close input immediately unless streaming in from a string buffer. see
        # below for remarks on why this is not a good idea with Windows EM. an
        # alternative is to pipe input from a command or a file in the command
        # line given to this method.
        process.stdin.close unless options[:input]

        # attach handlers to event machine and let it monitor incoming data. the
        # streams aren't used directly by the connectors except that they are
        # closed on unbind.
        stderr_eventable = ::EM.watch(process.stderr, ::RightScale::RightPopen::StdErrHandler, process, target, process.stderr) do |c|
          c.notify_readable = true
        end
        ::EM.watch(process.stdout, ::RightScale::RightPopen::StdOutHandler, process, target, stderr_eventable, process.stdout) do |c|
          c.notify_readable = true
          target.pid_handler(process.pid)

          # initial watch callback.
          #
          # note that we cannot abandon async watch; callback needs to interrupt
          # in this case
          target.watch_handler(process)
        end

        # the EM implementation is flawed so it is important to not create an
        # eventable for the input stream unless required. the issue stems from
        # EM thinking that file handles and socket handles come from the same
        # pool in the stdio libraries; in Linux they come from the same pool;
        # in Windows they come from different pools that increment
        # independendently and can coincidentally use the same ID numbers at an
        # unpredictable point in execution. confusing file numbers with socket
        # numbers can lead to treating sockets as files and vice versa with
        # unexpected failures for read/write access, etc.
        if options[:input]
          ::EM.attach(process.stdin, ::RightScale::RightPopen::StdInHandler, options, process.stdin)
        end

        # create a periodic watcher only if needed because the exit handler is
        # tied to EM eventable detachment.
        if process.needs_watching?
          ::EM.next_tick do
            watch_process(process, 0.1, target)
          end
        end
      rescue Exception => e
        # we can't raise from the main EM thread or it will stop EM.
        # the spawn method will signal the exit handler but not the
        # pid handler in this case since there is no pid. any action
        # (logging, etc.) associated with the failure will have to be
        # driven by the exit handler.
        if target
          target.async_exception_handler(e) rescue nil
          status = process && process.status
          status ||= ::RightScale::RightPopen::ProcessStatus.new(nil, 1)
          target.exit_handler(status)
        end
      end
    end

    # note that control returns to the caller, but the launched cmd continues
    # running and sends output to the handlers. the caller is not responsible
    # for waiting for the process to terminate or closing streams as the
    # watched eventables will handle this automagically. notification will be
    # sent to the exit_handler on process termination.
    true
  end

  # watches process for interrupt criteria. doubles the wait time up to a
  # maximum of 1 second for next wait.
  #
  # === Parameters
  # @param [Process] process that was run
  # @param [Numeric] wait_time as seconds to wait before checking status
  # @param [Object] target for handler calls
  #
  # === Return
  # true:: Always return true
  def self.watch_process(process, wait_time, target)
    ::EM::Timer.new(wait_time) do
      begin
        if process.alive?
          if process.timer_expired? || process.size_limit_exceeded?
            process.interrupt
          else
            # cannot abandon async watch; callback needs to interrupt in this case
            target.watch_handler(process)
          end
          watch_process(process, [wait_time * 2, 1].min, target)
        end
      rescue Exception => e
        # we can't raise from the main EM thread or it will stop EM.
        # the spawn method will signal the exit handler but not the
        # pid handler in this case since there is no pid. any action
        # (logging, etc.) associated with the failure will have to be
        # driven by the exit handler.
        if target
          target.async_exception_handler(e) rescue nil
          target.exit_handler(process.status) rescue nil if process
        end
      end
    end
    true
  end

end
