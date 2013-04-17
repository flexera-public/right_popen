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

require ::File.expand_path(::File.join(::File.dirname(__FILE__), 'process'))

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
      data = ::RightScale::RightPopen.async_read(@stream_out)
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
      # We force the stderr watched handler to go away so that
      # we don't end up with a broken pipe
      @stderr_eventable.force_detach if @stderr_eventable
      @target.timeout_handler if @process.timer_expired?
      @target.size_limit_handler if @process.size_limit_exceeded?
      @target.exit_handler(get_status)
      @stream_out.close
    end
  end

  # ensure uniqueness of handler to avoid confusion.
  raise "#{StdErrHandler.name} is already defined" if defined?(StdErrHandler)

  # Provides an eventmachine callback handler for the stderr stream.
  module StdErrHandler

    # === Parameters
    # @param [Object] target defining handler methods to be called
    # @param [IO] stream_err as standard error stream
    def initialize(target, stream_err)
      @target = target
      @stderr_handler = target.method(:stderr_handler)
      @stream_err = stream_err
      @unbound = false
    end

    # Callback from EM to asynchronously read the stderr stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8
    def notify_readable
      # call native win32 implementation for async_read
      data = ::RightScale::RightPopen.async_read(@stream_err)
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
    end

    # Forces detachment of the stderr handler on EM's next tick.
    def force_detach
      # Use next tick to prevent issue in EM where descriptors list
      # gets out-of-sync when calling detach in an unbind callback
      ::EM.next_tick { detach unless @unbound }
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

      # close input immediately unless streaming. the EM implementation is
      # flawed so it is important to not create an eventable for the input
      # stream unless required. the issue stems from EM thinking that file
      # handles and socket handles come from the same pool in the stdio
      # libraries; in Linux they come from the same pool, in Windows they don't.
      process.stdin.close unless options[:input]

      # attach handlers to event machine and let it monitor incoming data. the
      # streams aren't used directly by the connectors except that they are
      # closed on unbind.
      stderr_eventable = ::EM.watch(process.stderr, ::RightScale::RightPopen::StdErrHandler, target, process.stderr) do |c|
        c.notify_readable = true
      end
      ::EM.watch(process.stdout, ::RightScale::RightPopen::StdOutHandler, process, target, stderr_eventable, process.stdout) do |c|
        c.notify_readable = true
        target.pid_handler(process.pid)
      end
      if options[:input]
        ::EM.attach(process.stdin, ::RightScale::RightPopen::StdInHandler, options, process.stdin)
      end

      # create a watcher only if needed in the win32 async case because the
      # exit handler is tied to EM eventable detachment.
      if process.needs_watching?
        ::EM.next_tick do
          watch_process(process, 0.1, target)
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
      if process.alive?
        if process.timer_expired? || process.size_limit_exceeded?
          process.interrupt
        else
          # cannot abandon async watch; callback needs to interrupt in this case
          target.watch_handler(self)
        end
        watch_process(process, [wait_time * 2, 1].min, target)
      end
    end
    true
  end

end
