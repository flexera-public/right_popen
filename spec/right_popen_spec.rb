require File.join(File.dirname(__FILE__), 'spec_helper')

describe 'RightScale::popen3' do

  module RightPopenSpec
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

  def is_windows?
    return !!(RUBY_PLATFORM =~ /mswin/)
  end

  it 'should redirect output' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 0
    status.output_text.should == STANDARD_MESSAGE + "\n"
    status.error_text.should == ERROR_MESSAGE + "\n"
    status.pid.should > 0
  end

  it 'should return the right status' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_status.rb'))}\" #{EXIT_STATUS}"
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == EXIT_STATUS
    status.output_text.should == ''
    status.error_text.should == ''
    status.pid.should > 0
  end

  it 'should correctly handle many small processes' do
    pending 'Set environment variable TEST_STRESS to enable' unless ENV['TEST_STRESS']
    TO_RUN = 100
    command = is_windows? ? "cmd.exe /c exit 0" : "exit 0"
    runner = RightPopenSpec::Runner.new
    @completed = 0
    @started = 0
    run_cmd = Proc.new do
      runner.do_right_popen(command) do |status|
        @completed += 1
        status.status.exitstatus.should == 0
        status.output_text.should == ''
        status.error_text.should == ''
        status.pid.should > 0
      end
      @started += 1
      if @started < TO_RUN
        EM.next_tick { run_cmd.call }
      end
    end
    EM.run do
      EM.next_tick { run_cmd.call }

      EM::PeriodicTimer.new(1) do
        if @completed >= TO_RUN
          EM.stop
        end
      end
    end
  end

  it 'should preserve the integrity of stdout when stderr is unavailable' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stdout_only.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 0

    results = ''
    count.times do |i|
      results << "stdout #{i}\n"
    end
    status.output_text.should == results
    status.error_text.should == ''
    status.pid.should > 0
  end

  it 'should preserve the integrity of stderr when stdout is unavailable' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stderr_only.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 0

    results = ''
    count.times do |i|
      results << "stderr #{i}\n"
    end
    status.error_text.should == results
    status.output_text.should == ''
    status.pid.should > 0
  end

  it 'should preserve the integrity of stdout and stderr despite interleaving' do
    count = LARGE_OUTPUT_COUNTER
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_mixed_output.rb'))}\" #{count}"
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 99

    results = ''
    count.times do |i|
      results << "stdout #{i}\n"
    end
    status.output_text.should == results

    results = ''
    count.times do |i|
      (results << "stderr #{i}\n") if 0 == i % 10
    end
    status.error_text.should == results
    status.pid.should > 0
  end

  it 'should setup environment variables' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 0
    status.output_text.should_not include('_test_')
    status = runner.run_right_popen(command, :__test__ => '42')
    status.status.exitstatus.should == 0
    status.output_text.should match(/^__test__=42$/)
    status.pid.should > 0
  end

  it 'should restore environment variables' do
    begin
      ENV['__test__'] = '41'
      old_envs = {}
      ENV.each { |k, v| old_envs[k] = v }
      command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
      runner = RightPopenSpec::Runner.new
      status = runner.run_right_popen(command, :__test__ => '42')
      status.status.exitstatus.should == 0
      status.output_text.should match(/^__test__=42$/)
      ENV.each { |k, v| old_envs[k].should == v }
      old_envs.each { |k, v| ENV[k].should == v }
      status.pid.should > 0
    ensure
      ENV.delete('__test__')
    end
  end

  if is_windows?
    # FIX: this behavior is currently specific to Windows but should probably be
    # implemented for Linux.
    it 'should merge the PATH variable instead of overriding it' do
      command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
      runner = RightPopenSpec::Runner.new
      status = runner.run_right_popen(command, 'PATH' => "c:/bogus\\bin")
      status.status.exitstatus.should == 0
      status.output_text.should include('PATH=c:\\bogus\\bin;')
      status.pid.should > 0
    end
  else
    it 'should allow running bash command lines starting with a built-in command' do
      command = "for i in 1 2 3 4 5; do echo $i;done"
      runner = RightPopenSpec::Runner.new
      status = runner.run_right_popen(command)
      status.status.exitstatus.should == 0
      status.output_text.should == "1\n2\n3\n4\n5\n"
      status.pid.should > 0
    end

    it 'should support running background processes' do
      command = "(sleep 20)&"
      now = Time.now
      runner = RightPopenSpec::Runner.new
      status = runner.run_right_popen(command)
      finished = Time.now
      (finished - now).should < 20
      status.did_timeout.should be_false
      status.status.exitstatus.should == 0
      status.output_text.should == ""
      status.pid.should > 0
    end
  end

  it 'should support raw command arguments' do
    command = is_windows? ? ["cmd.exe", "/c", "echo", "*"] : ["echo", "*"]
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command)
    status.status.exitstatus.should == 0
    status.output_text.should == "*\n"
    status.pid.should > 0
  end

  it 'should run repeatedly without leaking resources' do
    pending 'Set environment variable TEST_LEAK to enable' unless ENV['TEST_LEAK']
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command, nil, nil, REPEAT_TEST_COUNTER)
    status.status.exitstatus.should == 0
    status.output_text.should == STANDARD_MESSAGE + "\n"
    status.error_text.should == ERROR_MESSAGE + "\n"
    status.pid.should > 0
  end

  it 'should pass input to child process' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'increment.rb'))}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command, nil, "42\n")
    status.status.exitstatus.should == 0
    status.output_text.should == "43\n"
    status.error_text.should be_empty
    status.pid.should > 0
  end

  it 'should handle child processes that close stdout but keep running' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'stdout.rb'))}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command, nil, nil)
    status.did_timeout.should be_true
    status.output_text.should be_empty
    status.error_text.should == "Closing stdout\n"
  end

  it 'should handle child processes that spawn long running background processes' do
    command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'background.rb'))}\""
    runner = RightPopenSpec::Runner.new
    status = runner.run_right_popen(command, nil, nil)
    status.status.exitstatus.should == 0
    status.did_timeout.should be_false
    status.output_text.should be_empty
    status.error_text.should be_empty
  end
end
