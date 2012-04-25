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
      def initialize(command, options={}, &callback)
        options = {:force_yield=>nil, :timeout=>nil, :expect_timeout=>false}.merge(options)
        @output_text = ""
        @error_text  = ""
        @status      = nil
        @did_timeout = false
        @callback    = callback
        @pid         = nil
        @force_yield = options[:force_yield]
        EM.next_tick do
          @timeout = EM::Timer.new(options[:timeout] || 2) do
            puts "\n** Failed to run #{command.inspect}: Timeout" unless options[:expect_timeout]
            @did_timeout = true
            @callback.call(self) if options[:expect_timeout]
          end
        end
      end

      attr_accessor :output_text, :error_text, :status, :did_timeout, :pid

      def on_read_stdout(data)
        sleep @force_yield if @force_yield
        @output_text << data
      end

      def on_read_stderr(data)
        sleep @force_yield if @force_yield
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

    def do_right_popen(command, options={}, &callback)
      options = {:env=>nil, :input=>nil, :timeout=>nil, :force_yield=>nil, :expect_timeout=>false}.merge(options)
      status = RunnerStatus.new(command, options, &callback)
      RightScale.popen3(:command        => command,
                        :input          => options[:input],
                        :target         => status,
                        :environment    => options[:env],
                        :stdout_handler => :on_read_stdout,
                        :stderr_handler => :on_read_stderr,
                        :pid_handler    => :on_pid,
                        :exit_handler   => :on_exit)
      status
    end

    def run_right_popen(command, options={}, &callback)
      options = {:repeats=>1, :env=>nil, :input=>nil, :timeout=>nil, :force_yield=>nil, :expect_timeout=>false}.merge(options)
      begin
        @iterations = 0
        @repeats = options[:repeats]
        @stats = []
        EM.run do
          EM.defer do
            do_right_popen(command, options) do |status|
              maybe_continue(status, command, options, &callback)
            end
          end
        end
        @stats.size < 2 ? @stats.first : @stats
      rescue Exception => e
        puts "\n** Failed: #{e.message} FROM\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    def maybe_continue(status, command, options, &callback)
      @iterations += 1
      @stats << status
      callback.call(status) if callback
      if @iterations < @repeats
        EM.defer do
          do_right_popen(command, options) do |status|
            maybe_continue(status, command, options, &callback)
          end
        end
      else
        EM.stop
      end
    end
  end
end
