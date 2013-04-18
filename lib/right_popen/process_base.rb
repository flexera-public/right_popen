#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2013 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'thread'

module RightScale
  module RightPopen
    class ProcessBase

      class ProcessError < Exception; end

      attr_reader :pid, :stdin, :stdout, :stderr, :status_fd, :status

      # === Parameters
      # @param [Hash] options see RightScale.popen3_async for details
      def initialize(options={})
        @options = options
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @status_fd = nil
        @last_interrupt = nil
        @pid = nil
        @stop_time = nil
        @watch_directory = nil
        @size_limit_bytes = nil
        @cmd = nil
        @target = nil
        @status = nil
        @needs_watching = !!(
          @options[:timeout_seconds] ||
          @options[:size_limit_bytes] ||
          @options[:watch_handler])
      end

      # Determines if the process is still running.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if running
      def alive?
        raise NotImplementedError, 'Must be overridden'
      end

      # Determines if this process needs to be watched (beyond waiting for the
      # process to exit).
      #
      # === Return
      # @return [TrueClass|FalseClass] true if needs watching
      def needs_watching?; @needs_watching; end

      # Determines if timeout on child process has expired, if any.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if timer expired
      def timer_expired?
        !!(@stop_time && Time.now > @stop_time)
      end

      # Determines if total size of files created by child process has exceeded
      # the limit specified, if any.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if size limit exceeded
      def size_limit_exceeded?
        if @watch_directory
          globbie = ::File.join(@watch_directory, '**/*')
          size = 0
          ::Dir.glob(globbie) do |f|
            size += ::File.stat(f).size rescue 0 if ::File.file?(f)
            break if size > @size_limit_bytes
          end
          size > @size_limit_bytes
        else
          false
        end
      end

      # @return [TrueClass|FalseClass] interrupted as true if child process was interrupted by watcher
      def interrupted?; !!@last_interrupt; end

      # spawns a child process using given command and handler target in a
      # platform-independant manner.
      #
      # must be overridden and override must call super.
      #
      # === Parameters
      # @param [String|Array] cmd as shell command or binary to execute
      # @param [Object] target that implements all handlers (see TargetProxy)
      #
      # === Return
      # @return [TrueClass] always true
      def spawn(cmd, target)
        @cmd = cmd
        @target = target
        @kill_time = nil
        @pid = nil
        @status = nil

        if @size_limit_bytes = @options[:size_limit_bytes]
          @watch_directory = @options[:watch_directory] || @options[:directory] || ::Dir.pwd
        end

        @start_time = ::Time.now
        @stop_time  = @options[:timeout_seconds] ?
                      (@start_time + @options[:timeout_seconds]) :
                      nil
      end

      # Monitors I/O from child process and directly notifies target of any
      # events. Blocks until child exits.
      #
      # === Return
      # @return [TrueClass] always true
      def sync_exit_with_target
        # early handling in case caller wants to stream to/from the pipes
        # directly (as in a classic popen3/4 scenario).
        begin
          @target.pid_handler(@pid)
          if input_text = @options[:input]
            @stdin.write(input_text)
          end

          # sync watch_handler has the option to abandon watch as soon as child
          # process comes alive and before streaming any output.
          if @target.watch_handler(self)
            # can close stdin if not returning control to caller.
            @stdin.close rescue nil
          else
            # caller is reponsible for draining and closing all pipes.
            return true
          end
        rescue
          safe_close_io
          raise
        end

        # note that calling IO.select on pipes which have already had all
        # of their output consumed can cause segfault (in Ubuntu?) so it is
        # important to keep track of when all I/O has been consumed.
        channels_to_finish = {
          :stdout_handler => @stdout,
          :stderr_handler => @stderr
        }
        channels_to_finish[:status_fd] = @status_fd if @status_fd
        abandon = false
        last_exception = nil
        begin
          while !channels_to_finish.empty?
            channels_to_watch = channels_to_finish.values.dup
            ready = ::IO.select(channels_to_watch, nil, nil, 0.1) rescue nil
            dead = !alive?
            if ready
              ready.first.each do |channel|
                key = channels_to_finish.find { |k, v| v == channel }.first
                data = dead ? channel.gets(nil) : channel.gets
                if data
                  if key == :status_fd
                    last_exception = ::Marshal.load(data)
                  else
                    @target.method(key).call(data)
                  end
                else
                  # nothing on channel indicates EOF
                  channels_to_finish.delete(key)
                end
              end
            end
            if dead
              channels_to_finish = {}
            elsif (interrupted? || timer_expired? || size_limit_exceeded?)
              interrupt
            elsif abandon = !@target.watch_handler(self)
              return true  # bypass any remaining callbacks
            end
          end
          wait_for_exit_status
          @target.timeout_handler if timer_expired?
          @target.size_limit_handler if size_limit_exceeded?
          @target.exit_handler(@status)

          # re-raise exception from fork, if any.
          case last_exception
          when nil
            # all good
          when ::Exception
            raise last_exception
          else
            raise "Unknown failure: saw #{last_exception.inspect} on status channel."
          end
        ensure
          # abandon will not close I/O objects; caller takes responsibility via
          # process object passed to watch_handler. if anyone calls interrupt
          # then close I/O regardless of abandon to try to force child to die.
          safe_close_io if !abandon || interrupted?
        end
        true
      end

      # blocks waiting for process exit status.
      #
      # === Return
      # @return [ProcessStatus] exit status
      def wait_for_exit_status
        raise NotImplementedError, 'Must be overridden'
      end

      # @return [Array] escalating termination signals for this platform
      def signals_for_interrupt
        raise NotImplementedError, 'Must be overridden'
      end

      # Interrupts the running process (without abandoning watch) in increasing
      # degrees of signalled severity.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if process was alive and interrupted, false if dead before (first) interrupt
      def interrupt
        while alive?
          if !@kill_time || Time.now >= @kill_time
            # soft then hard interrupt (assumed to be called periodically until
            # process is gone).
            sigs = signals_for_interrupt
            if @last_interrupt
              last_index = sigs.index(@last_interrupt)
              next_interrupt = sigs[last_index + 1]
            else
              next_interrupt = sigs.first
            end
            unless next_interrupt
              raise ::RightScale::RightPopen::ProcessBase::ProcessError
                    'Unable to kill child process'
            end
            @last_interrupt = next_interrupt

            result = ::Process.kill(next_interrupt, @pid) rescue nil
            if result
              @kill_time = Time.now + 3 # more seconds until next attempt
              break
            end
          end
        end
        interrupted?
      end

      # Safely closes any open I/O objects associated with this process.
      #
      # === Return
      # @return [TrueClass] alway true
      def safe_close_io
        @stdin.close rescue nil if @stdin && !@stdin.closed?
        @stdout.close rescue nil if @stdout && !@stdout.closed?
        @stderr.close rescue nil if @stderr && !@stderr.closed?
        @status_fd.close rescue nil if @status_fd && !@status_fd.closed?
        true
      end

    end
  end
end
