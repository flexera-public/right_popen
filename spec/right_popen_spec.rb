require File.join(File.dirname(__FILE__), 'spec_helper')

RUBY_CMD         = 'ruby'
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

# manually bump count up for more aggressive multi-processor testing, lessen
# for a quick smoke test
LARGE_OUTPUT_COUNTER = 1000

# bump up count for most exhaustive leak detection.
REPEAT_TEST_COUNTER = 256

def is_windows?
  return RUBY_PLATFORM =~ /mswin/
end

describe 'RightScale::popen3' do

  module RightPopenSpec

    class Runner
      def initialize
        @done           = false
        @output_text    = nil
        @error_text     = nil
        @status         = nil
        @last_exception = nil
        @did_timeout    = false
        @last_iteration = 0
      end

      attr_reader :output_text, :error_text, :status, :did_timeout

      def do_right_popen(command, env=nil, input=nil)
        @timeout = EM::Timer.new(2) { @did_timeout = true; puts "\n** Failed to run #{command.inspect}: Timeout"; EM.stop }
        @output_text = ''
        @error_text  = ''
        @status      = nil
        @did_timeout = false
        RightScale.popen3(:command        => command, 
                          :input          => input,
                          :target         => self, 
                          :environment    => env,
                          :stdout_handler => :on_read_stdout, 
                          :stderr_handler => :on_read_stderr, 
                          :exit_handler   => :on_exit)
      end

      def run_right_popen(command, env=nil, input=nil, count=1)
        begin
          @command = command
          @env = env
          @last_iteration = 0
          @count = count
          puts "#{count}>" if count > 1
          EM.run { EM.next_tick { do_right_popen(command, env, input) } }
        rescue Exception => e
          puts "\n** Failed: #{e.message} FROM\n#{e.backtrace.join("\n")}"
          raise e
        end
      end

      def on_read_stdout(data)
        @output_text << data
      end

      def on_read_stderr(data)
        @error_text << data
      end

      def on_exit(status)
        @last_iteration += 1
        @timeout.cancel if @timeout
        if @last_iteration < @count
          EM.next_tick do
            print '+'
            STDOUT.flush
            do_right_popen(@command, @env)
          end
        else
          puts "<" if @count > 1
          EM.stop
        end
        @status = status
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
  
  it 'should setup environment variables' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command)
    runner.status.exitstatus.should == 0
    runner.output_text.should_not include('_test_')
    runner.run_right_popen(command, :__test__ => '42')
    runner.status.exitstatus.should == 0
    runner.output_text.should match(/^__test__=42$/)
  end

  it 'should restore environment variables' do
    ENV['__test__'] = '41'
    old_envs = {}
    ENV.each { |k, v| old_envs[k] = v }
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, :__test__ => '42')
    runner.status.exitstatus.should == 0
    runner.output_text.should match(/^__test__=42$/)
    ENV.each { |k, v| old_envs[k].should == v }
    old_envs.each { |k, v| ENV[k].should == v }
  end

  if is_windows?
    # FIX: this behavior is currently specific to Windows but should probably be
    # implemented for Linux.
    it 'should merge the PATH variable instead of overriding it' do
      command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
      runner = RightPopenSpec::Runner.new
      runner.run_right_popen(command, 'PATH' => "c:/bogus\\bin")
      runner.status.exitstatus.should == 0
      runner.output_text.should include('PATH=c:\\bogus\\bin;')
    end
  else
    it 'should allow running bash command lines starting with a built-in command' do
      command = "for i in 1 2 3 4 5; do echo $i;done"
      runner = RightPopenSpec::Runner.new
      runner.run_right_popen(command)
      runner.status.exitstatus.should == 0
      runner.output_text.should == "1\n2\n3\n4\n5\n"
    end
  end

  it 'should run repeatedly without leaking resources' do
    pending 'Set environment variable TEST_LEAK to enable' unless ENV['TEST_LEAK']
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, nil, nil, REPEAT_TEST_COUNTER)
    runner.status.exitstatus.should == 0
    runner.output_text.should == STANDARD_MESSAGE + "\n"
    runner.error_text.should == ERROR_MESSAGE + "\n"
  end

  it 'should pass input to child process' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'increment.rb'))}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, nil, "42\n")
    runner.status.exitstatus.should == 0
    runner.output_text.should == "43\n"
    runner.error_text.should be_empty
  end

  it 'should handle child processes that close stdout but keep running' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'stdout.rb'))}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, nil, nil)
    runner.did_timeout.should be_true
    runner.output_text.should be_empty
    runner.error_text.should == "Closing stdout\n"
  end

  it 'should handle child processes that spawn long running background processes' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'background.rb'))}\""
    runner = RightPopenSpec::Runner.new
    runner.run_right_popen(command, nil, nil)
    runner.status.exitstatus.should == 0
    runner.did_timeout.should be_false
    runner.output_text.should be_empty
    runner.error_text.should be_empty
  end
end
