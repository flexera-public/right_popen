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

require 'rubygems'
require 'eventmachine'
require 'win32/process'

require File.join(File.dirname(__FILE__), 'right_popen.so')  # win32 native code

module RightScale

  # Provides an eventmachine callback handler for the stdout stream.
  module StdOutHandler

    # Quacks like Process::Status, which we cannot instantiate ourselves because
    # has no public new method. RightScale::popen3 needs this because the
    # 'win32/process' gem currently won't return Process::Status objects but
    # only returns a [pid, exitstatus] value.
    class Status
      # Process ID
      attr_reader :pid

      # Process exit code
      attr_reader :exitstatus

      # === Parameters
      # pid(Integer):: Process ID.
      # 
      # exitstatus(Integer):: Process exit code
      def initialize(pid, exitstatus)
        @pid = pid
        @exitstatus = exitstatus
      end

      # Simulates Process::Status.exited?
      #
      # === Returns
      # true in all cases because this object cannot be returned until the
      # process exits
      def exited?
        return true
      end

      # Simulates Process::Status.success?
      #
      # === Returns
      # true if the process returned zero as its exit code
      def success?
        return @exitstatus ? (0 == @exitstatus) : true;
      end
    end

    # === Parameters
    # target(Object):: Object defining handler methods to be called.
    # stdout_handler(String):: Token for stdout handler method name.
    # exit_handler(String):: Token for exit handler method name.
    # stderr_eventable(Connector):: EM object representing stderr handler.
    # stream_out(IO):: Standard output stream.
    # pid(Integer):: Child process ID.
    def initialize(target, stdout_handler, exit_handler, stderr_eventable, stream_out, pid)
      @target = target
      @stdout_handler = stdout_handler
      @exit_handler = exit_handler
      @stderr_eventable = stderr_eventable
      @stream_out = stream_out
      @pid = pid
      @status = nil
    end

    # Callback from EM to asynchronously read the stdout stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8
    def notify_readable
      data = RightPopen.async_read(@stream_out)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @target.method(@stdout_handler).call(data) if @stdout_handler
    end

    # Override of Connection.get_status() for Windows implementation.
    def get_status
      unless @status
        begin
          @status = Status.new(@pid, Process.waitpid2(@pid)[1])
        rescue Process::Error
          # process is gone, which means we have no recourse to retrieve the
          # actual exit code; let's be optimistic.
          @status = Status.new(@pid, 0)
        end
      end
      return @status
    end

    # Callback from EM to unbind.
    def unbind
      # We force the attached stderr handler to go away so that
      # we don't end up with a broken pipe
      @stderr_eventable.force_detach if @stderr_eventable
      @target.method(@exit_handler).call(get_status) if @exit_handler
      @stream_out.close
    end
  end

  # Provides an eventmachine callback handler for the stderr stream.
  module StdErrHandler

    # === Parameters
    # target(Object):: Object defining handler methods to be called.
    #
    # stderr_handler(String):: Token for stderr handler method name.
    # 
    # stream_err(IO):: Standard error stream.
    def initialize(target, stderr_handler, stream_err)
      @target = target
      @stderr_handler = stderr_handler
      @stream_err = stream_err
      @unbound = false
    end

    # Callback from EM to asynchronously read the stderr stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8
    def notify_readable
      data = RightPopen.async_read(@stream_err)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @target.method(@stderr_handler).call(data)
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
      EM.next_tick { detach unless @unbound }
    end
  end

  # Creates a child process and connects event handlers to the standard output
  # and error streams used by the created process. Connectors use named pipes
  # and asynchronous I/O in the native Windows implementation.
  #
  # See RightScale.popen3
  def self.popen3_imp(options)
    raise "EventMachine reactor must be started" unless EM.reactor_running?

    # launch cmd and request asynchronous output (which is only provided by
    # the RightScale version of win32/open3 gem).
    mode = "t"
    show_window = false
    asynchronous_output = true
    stream_in, stream_out, stream_err, pid = RightPopen.popen4(options[:command], mode, show_window, asynchronous_output)

    # close input immediately.
    stream_in.close

    # attach handlers to event machine and let it monitor incoming data. the
    # streams aren't used directly by the connectors except that they are closed
    # on unbind.
    stderr_eventable = EM.attach(stream_err, StdErrHandler, options[:target], options[:stderr_handler], stream_err) if stderr_handler
    EM.attach(stream_out, StdOutHandler, options[:target], options[:stdout_handler], options[:exit_handler], stderr_eventable, stream_out, pid)

    # note that control returns to the caller, but the launched cmd continues
    # running and sends output to the handlers. the caller is not responsible
    # for waiting for the process to terminate or closing streams as the
    # attached eventables will handle this automagically. notification will be
    # sent to the exit_handler on process termination.
  end

end
