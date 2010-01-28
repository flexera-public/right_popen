require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_popen'

RUBY_CMD         = 'ruby'
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

# manually bump count up for more aggressive multi-processor testing, lessen
# for a quick smoke test
LARGE_OUTPUT_COUNTER = 1000

describe 'RightScale::popen3' do

  module RightPopenSpec

    class Runner
      def initialize
        @done        = false
        @output_text = ''
        @error_text  = ''
        @status      = nil
      end

      attr_reader :output_text, :error_text, :status

      def run_right_popen(command)
        EM.next_tick do
          RightScale.popen3(command, self, :on_read_stdout, :on_read_stderr, :on_exit)
        end
        EM.run do
          timer = EM::PeriodicTimer.new(0.1) do
            if @done
              timer.cancel
              EM.stop
            end
          end
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

end
