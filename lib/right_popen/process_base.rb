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

      attr_reader :pid, :stdin, :stdout, :stderr, :status_fd

      # === Parameters
      # @param [Hash] options see RightScale.popen3_async for details
      def initialize(options={})
        @options = options
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @status_fd = nil
        @alive = false
        @interrupted = false
        @pid = nil
        @stop_time = nil
        @watch_directory = nil
        @size_limit_bytes = nil
        @cmd = nil
        @target = nil
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
      def interrupted?; !!@interrupted; end

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
        @next_kill_signal = nil
        @alive = false

        if @size_limit_bytes = @options[:size_limit_bytes]
          @watch_directory = @options[:watch_directory] || @options[:directory] || ::Dir.pwd
        end

        @start_time = ::Time.now
        @stop_time  = @options[:timeout_seconds] ?
                      (@start_time + @options[:timeout_seconds]) :
                      nil
      end

      # Interrupts the running process (without abandoning watch) in increasing
      # degrees of signalled severity.
      #
      # === Return
      # @return [TrueClass] always true
      def interrupt
        raise NotImplementedError, 'Must be overridden'
      end

      # Creates a thread to monitor I/O from child process and notifies target
      # of any events until child exits.
      #
      # === Return
      # @return [TrueClass] always true
      def sync_exit_with_target
        raise NotImplementedError, 'Must be overridden'
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
