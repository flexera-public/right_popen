#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
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

module RightScale
  class Runner
    class RunnerStatus
      def initialize(command, block)
        @output_text = ""
        @error_text  = ""
        @status      = nil
        @did_timeout = false
        @callback    = block
        @pid         = nil
        EM.next_tick do
          @timeout = EM::Timer.new(2) do
            puts "\n** Failed to run #{command.inspect}: Timeout"
            @did_timeout = true
            @callback.call(self)
          end
        end
      end

      attr_accessor :output_text, :error_text, :status, :did_timeout, :pid

      def on_read_stdout(data)
        @output_text << data
      end

      def on_read_stderr(data)
        @error_text << data
      end

      def on_pid(pid)
        raise "PID already set!" unless @pid.nil?
        @pid = pid
      end

      def on_exit(status)
        @timeout.cancel if @timeout
        @status = status
        @callback.call(self)
      end
    end

    def initialize
      @count          = 0
      @done           = false
      @last_exception = nil
      @last_iteration = 0
    end

    def do_right_popen(command, env=nil, input=nil, &callback)
      status = RunnerStatus.new(command, callback)
      RightScale.popen3(:command        => command,
                      :input          => input,
                      :target         => status,
                      :environment    => env,
                      :stdout_handler => :on_read_stdout,
                      :stderr_handler => :on_read_stderr,
                      :pid_handler    => :on_pid,
                      :exit_handler   => :on_exit)
      status
    end

    def run_right_popen(command, env=nil, input=nil, count=1)
      begin
        @iterations = 0
        EM.run do
          EM.next_tick do
            do_right_popen(command, env, input) do |status|
              maybe_continue(status)
            end
          end
        end
        @status
      rescue Exception => e
        puts "\n** Failed: #{e.message} FROM\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    def maybe_continue(status)
      @iterations += 1
      if @iterations < @count
        do_right_popen(command, env, input) {|status| maybe_continue(status)}
      else
        @status = status
        EM.stop
      end
    end
  end
end
