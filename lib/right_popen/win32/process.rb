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

require 'win32/process'

require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'process_base'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', '..', 'win32', 'right_popen.so'))  # win32 native code

module RightScale
  module RightPopen
    class Process < ProcessBase

      def initialize(options={})
        super(options)
      end

      # Determines if the process is still running.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if running
      def alive?
        # kill zero is an existence check on all platforms; exception differs.
        !!::Process.kill(0, @pid)
      rescue Process::Error
        false
      end

      # spawns a child process using given command and handler target in a
      # win32-specific manner.
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
        super(cmd, target)

        # garbage collection has no good effect for spawning a child process in
        # Windows because forking is not supported and so Ruby objects cannot be
        # shared with child process (although handles can be shared via some
        # advanced API programming). the following GC call is only for
        # compatibility with the Linux implementation.
        ::GC.start

        # merge and format environment strings, if necessary.
        environment_hash = options[:environment] || {}
        environment_strings = ::RightScale::RightPopenEx.merge_environment(environment_hash)

        # resolve command string from array, if necessary.
        if cmd.kind_of?(::Array)
          escaped = []
          cmd.flatten.each do |arg|
            value = arg.to_s
            escaped << (value.index(' ') ? "\"#{value}\"" : value)
          end
          cmd = escaped.join(" ")
        end

        # launch cmd using native win32 implementation.
        @stdin, @stdout, @stderr, @pid = ::RightScale::RightPopen.popen4(
          cmd,
          mode = 't',
          show_window = false,
          asynchronous_output = true,
          environment_strings)
        true
      end

      # blocks waiting for process exit status.
      #
      # === Return
      # @return [Status] exit status
      def wait_for_exit_status
        exit_code = nil
        begin
          # note that win32-process gem doesn't support the no-hang parameter
          # and returns exit code instead of status.
          ignored, exit_code = ::Process.waitpid2(@pid)
        rescue Process::Error
          # process is gone, which means we have no recourse to retrieve the
          # actual exit code; let's be optimistic.
          exit_code = 0
        end
        ::RightScale::RightPopenEx::Status.new(process.pid, exit_code)
      end

      # Monitors I/O from child process and directly notifies target of any
      # events. Blocks until child exits.
      #
      # === Return
      # @return [TrueClass] always true
      def sync_exit_with_target
        # note that calling IO.select on pipes which have already had all
        # of their output consumed can cause segfault (in Ubuntu?) so it is
        # important to keep track of when all I/O has been consumed.
        channels_to_finish = {
          :stdout => @stdout,
          :stderr => @stderr
        }
        last_exception = nil
        begin
          if input_text = @options[:input]
            @stdin.write(input_text)
          end
        ensure
          @stdin.close rescue nil
        end
        while !channels_to_finish.empty?
          channels_to_watch = channels_to_finish.values.dup
          ready = ::IO.select(channels_to_watch, nil, nil, 0.1) rescue nil
          dead = !alive?
          if ready
            ready.first.each do |channel|
              key = channels_to_finish.find { |k, v| v == channel }.first
              line = dead ? channel.gets(nil) : channel.gets
              if line
                @target.method(key).call(line)
              else
                # nothing on channel indicates EOF
                channels_to_finish.delete(key)
              end
            end
          end
          if dead
            channels_to_finish = {}
          elsif (timer_expired? || size_limit_exceeded?)
            process.interrupt
          end
        end
        status = wait_for_exit_status
        @target.timeout_handler if timer_expired?
        @target.size_limit_handler if size_limit_exceeded?
        @target.exit_handler(status)
        true
      ensure
        @stdout.close rescue nil
        @stderr.close rescue nil
        @status_fd.close rescue nil
      end

    end
  end
end
