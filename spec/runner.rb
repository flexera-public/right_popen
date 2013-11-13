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

require 'rubygems'
require 'eventmachine'

module RightScale
  module RightPopen
    class Runner
      class RunnerStatus
        def initialize(command, options={}, &callback)
          options = {:repeats=>1, :force_yield=>nil, :timeout=>nil, :expect_timeout=>false}.merge(options)

          @command     = command
          @output_text = ""
          @error_text  = ""
          @status      = nil
          @did_timeout = false
          @callback    = callback
          @pid         = nil
          @force_yield = options[:force_yield]

          @expect_timeout    = options[:expect_timeout]
          @expect_size_limit = options[:expect_size_limit]
          @async_exception   = nil
        end

        attr_accessor :output_text, :error_text, :status, :pid
        attr_accessor :did_timeout, :did_size_limit, :async_exception

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

        def on_timeout
          puts "\n** Failed to run #{@command.inspect}: Timeout" unless @expect_timeout
          @did_timeout = true
          @callback.call(self) if @expect_timeout
        end

        def on_size_limit
          puts "\n** Failed to run #{@command.inspect}: Size limit" unless @expect_size_limit
          @did_size_limit = true
          @callback.call(self) if @expect_size_limit
        end

        def on_exit(status)
          @status = status
          @callback.call(self)
        end

        def on_async_exception(async_exception)
          @async_exception = async_exception
        end
      end

      def initialize
        @count          = 0
        @done           = false
        @last_exception = nil
        @last_iteration = 0
      end

      def run_right_popen3(synchronicity, command, runner_options={}, &callback)
        runner_options = {
          :repeats           => 1,
          :expect_timeout    => false,
          :expect_size_limit => false
        }.merge(runner_options)
        popen3_options = {
          :input            => runner_options[:input],
          :environment      => runner_options[:env],
          :timeout_seconds  => runner_options.has_key?(:timeout) ? runner_options[:timeout] : 2,
          :size_limit_bytes => runner_options[:size_limit_bytes],
          :watch_directory  => runner_options[:watch_directory],
          :user             => runner_options[:user],
          :group            => runner_options[:group],
        }
        case synchronicity
        when :sync
          run_right_popen3_sync(command, runner_options, popen3_options, &callback)
        when :async
          run_right_popen3_async(command, runner_options, popen3_options, &callback)
        else
          raise "unknown synchronicity = #{synchronicity.inspect}"
        end
      end

      def run_right_popen3_sync(command, runner_options, popen3_options, &callback)
        @iterations = 0
        @repeats = runner_options[:repeats]
        @stats = []
        while @iterations < @repeats
          @iterations += 1
          do_right_popen3_sync(command, runner_options, popen3_options) do |runner_status|
            @stats << runner_status
            callback.call(runner_status) if callback
            if @repeats > 1
              puts if 1 == (@iterations % 64)
              print '+'
              puts if @iterations == @repeats
            end
          end
        end
        @stats.uniq!
        @stats.size < 2 ? @stats.first : @stats
      end

      def run_right_popen3_async(command, runner_options, popen3_options, &callback)
        @iterations = 0
        @repeats = runner_options[:repeats]
        @stats = []
        last_exception = nil
        EM.run do
          EM.defer do
            begin
              do_right_popen3_async(command, runner_options, popen3_options) do |runner_status|
                last_exception ||= maybe_continue_popen3_async(runner_status, command, runner_options, popen3_options, &callback)
              end
            rescue Exception => e
              last_exception = e
              EM.stop
            end
          end
        end
        raise last_exception if last_exception
        @stats.uniq!
        @stats.size < 2 ? @stats.first : @stats
      end

      def do_right_popen3(synchronicity, command, runner_options, popen3_options, &callback)
        runner_status = RunnerStatus.new(command, runner_options, &callback)
        popen3_options = {
          :target                  => runner_status,
          :stdout_handler          => :on_read_stdout,
          :stderr_handler          => :on_read_stderr,
          :pid_handler             => :on_pid,
          :timeout_handler         => :on_timeout,
          :size_limit_handler      => :on_size_limit,
          :exit_handler            => :on_exit,
          :async_exception_handler => :on_async_exception
        }.merge(popen3_options)
        case synchronicity
        when :sync
          result = ::RightScale::RightPopen.popen3_sync(command, popen3_options)
        when :async
          result = ::RightScale::RightPopen.popen3_async(command, popen3_options)
        else
          raise "Uknown synchronicity = #{synchronicity.inspect}"
        end
        result.should == true
        true
      end

      def do_right_popen3_sync(command, runner_options, popen3_options, &callback)
        do_right_popen3(:sync, command, runner_options, popen3_options, &callback)
      end

      def do_right_popen3_async(command, runner_options, popen3_options, &callback)
        do_right_popen3(:async, command, runner_options, popen3_options, &callback)
      end

      def maybe_continue_popen3_async(runner_status, command, runner_options, popen3_options, &callback)
        @iterations += 1
        @stats << runner_status
        callback.call(runner_status) if callback
        last_exception = nil
        if @iterations < @repeats
          if @repeats > 1
            puts if 1 == (@iterations % 64)
            print '+'
            puts if @iterations == @repeats
          end
          EM.defer do
            begin
              do_right_popen3_async(command, runner_options, popen3_options) do |runner_status2|
                last_exception ||= maybe_continue_popen3_async(runner_status2, command, runner_options, popen3_options, &callback)
              end
            rescue Exception => e
              last_exception = e
              EM.stop
            end
          end
        else
          EM.stop
        end
        last_exception ||= runner_status.async_exception
        last_exception
      end
    end
  end
end
