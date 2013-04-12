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
      attr_reader :stdin, :stdout, :stderr, :pid

      # === Parameters
      # @param [Hash] options see RightScale.popen3_async for details
      def initialize(options={})
        @options = options
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @status_fd = nil
        @pid = nil
        @stop_time = nil
        @watch_directory = nil
        @size_limit_bytes = nil
        @cmd = nil
        @target = nil
      end

      # Determines if this process needs to be watched (beyond waiting for the
      # process to exit).
      #
      # === Return
      # @return [TrueClass|FalseClass] true if needs watching
      def needs_watching?
        !!(@stop_time || @watch_directory)
      end

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
        @next_kill_signal = 'INT'

        if @size_limit_bytes = @options[:size_limit_bytes]
          @watch_directory = @options[:watch_directory] || @options[:directory] || ::Dir.pwd
        end

        @start_time = ::Time.now
        @stop_time  = @options[:timeout_seconds] ?
                      (@start_time + @options[:timeout_seconds]) :
                      nil
      end

      def interrupt
        if (::Process.kill(0, @pid) rescue nil)
          # interrupt.
          ::Process.kill(@next_kill_signal, @pid) rescue nil

          # soft then hard interrupt (assumed to be called periodically until
          # process is gone).
          @next_kill_signal = 'KILL'
        end
        true
      end

      # Creates a thread to monitor I/O from child process and notifies target
      # of any events until child exits.
      #
      # === Return
      # @return [TrueClass] always true
      def sync_exit_with_target
        raise NotImplementedError, 'Must be overridden'
      end

    end
  end
end
