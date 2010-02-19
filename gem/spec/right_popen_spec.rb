require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_popen'

RUBY_CMD         = 'ruby'
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

# manually bump count up for more aggressive multi-processor testing, lessen
# for a quick smoke test
LARGE_OUTPUT_COUNTER = 1000

# bump up count for most exhaustive leak detection.
REPEAT_TEST_COUNTER = 256

describe 'RightScale::popen3' do

  module RightPopenSpec

    class Runner
      def initialize
        @done           = false
        @output_text    = nil
        @error_text     = nil
        @status         = nil
        @last_exception = nil
        @last_iteration = 0
      end

      attr_reader :output_text, :error_text, :status

      def do_right_popen(command)
        @output_text = ''
        @error_text  = ''
        @status      = nil
        RightScale.popen3(:command        => command, 
                          :target         => self, 
                          :stdout_handler => :on_read_stdout, 
                          :stderr_handler => :on_read_stderr, 
                          :exit_handler   => :on_exit)
      end

      def run_right_popen(command, count = 1)
        puts "#{count}>" if count > 1
        last_iteration = 0
        EM.next_tick do
          do_right_popen(command)
        end
        EM.run do
          timer = EM::PeriodicTimer.new(0.05) do
            begin
              if @done || @last_exception
                last_iteration = last_iteration + 1
                if @last_exception.nil? && last_iteration < count
                  @done = false
                  EM.next_tick do
                    if count > 1
                      print '+'
                      STDOUT.flush
                    end
                    do_right_popen(command)
                  end
                else
                  puts "<" if count > 1
                  timer.cancel
                  EM.stop
                end
              end
            rescue Exception => e
              @last_exception = e
              timer.cancel
              EM.stop
            end
          end
        end
        if @last_exception
          if count > 1
            message = "<#{last_iteration + 1}\n#{last_exception.message}"
          else
            message = last_exception.message
          end
          raise @last_exception.class, "#{message}\n#{@last_exception.backtrace.join("\n")}"
        end
      end

      def on_read_stdout(data)
        @output_text << data
      end

      def on_read_stderr(data)
        @error_text << data
      end

      def on_exit(status)
        @status = status
        @done = true
      end
    end

  end

  it 'should redirect output' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == 0
    runner.output_text.should == STANDARD_MESSAGE + "\n"
    runner.error_text.should == ERROR_MESSAGE + "\n"
  end

  it 'should return the right status' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_status.rb'))}\" #{EXIT_STATUS}"
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == EXIT_STATUS
    runner.output_text.should == ''
    runner.error_text.should == ''
  end

  it 'should preserve the integrity of stdout when stderr is unavailable' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stdout_only.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == 0

    results = ''
    count.times do |i|
      results << "stdout #{i}\n"
    end
    runner.output_text.should == results
    runner.error_text.should == ''
  end

  it 'should preserve the integrity of stderr when stdout is unavailable' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stderr_only.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == 0

    results = ''
    count.times do |i|
      results << "stderr #{i}\n"
    end
    runner.error_text.should == results
    runner.output_text.should == ''
  end

  it 'should preserve the integrity of stdout and stderr despite interleaving' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_mixed_output.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == 99

    results = ''
    count.times do |i|
      results << "stdout #{i}\n"
    end
    runner.output_text.should == results

    results = ''
    count.times do |i|
      (results << "stderr #{i}\n") if 0 == i % 10
    end
    runner.error_text.should == results
  end

  it 'should run repeatedly without leaking resources' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, REPEAT_TEST_COUNTER)
    runner.status.exitstatus.should == 0
    runner.output_text.should == STANDARD_MESSAGE + "\n"
    runner.error_text.should == ERROR_MESSAGE + "\n"
  end

end
