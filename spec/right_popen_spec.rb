require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), 'runner'))

require 'stringio'
require 'tmpdir'

describe 'RightScale::RightPopen' do
  def is_windows?
    return !!(RUBY_PLATFORM =~ /mswin|mingw/)
  end

  let(:runner) { ::RightScale::RightPopen::Runner.new }

  it "should correctly handle many small processes [async]" do
    pending 'Set environment variable TEST_STRESS to enable' unless ENV['TEST_STRESS']
    run_count = 100
    command = is_windows? ? ['cmd.exe', '/c', 'exit 0'] : ['sh', '-c', 'exit 0']
    @completed = 0
    @started = 0
    run_cmd = Proc.new do
      runner.do_right_popen3_async(command, runner_options={}, popen3_options={}) do |runner_status|
        @completed += 1
        runner_status.status.exitstatus.should == 0
        runner_status.output_text.should == ''
        runner_status.error_text.should == ''
        runner_status.pid.should > 0
      end
      @started += 1
      if @started < run_count
        EM.next_tick { run_cmd.call }
      end
    end
    EM.run do
      EM.next_tick { run_cmd.call }

      EM::PeriodicTimer.new(1) do
        if @completed >= run_count
          EM.stop
        end
      end
    end
  end

  [:sync, :async].each do |synchronicity|

    context synchronicity do

      it "should redirect output" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
        runner_status = runner.run_right_popen3(synchronicity, command)
        runner_status.should_not be_nil
        runner_status.status.should_not be_nil
        runner_status.status.exitstatus.should == 0
        runner_status.output_text.should == STANDARD_MESSAGE + "\n"
        runner_status.error_text.should == ERROR_MESSAGE + "\n"
        runner_status.pid.should > 0
      end

      it "should return the right status" do
        ruby = `which ruby`.chomp  # which is assumed to be on the PATH for the Windows case
        command = [
          ruby,
          File.expand_path(File.join(File.dirname(__FILE__), 'produce_status.rb')),
          EXIT_STATUS
        ]
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == EXIT_STATUS
        status.output_text.should == ''
        status.error_text.should == ''
        status.pid.should > 0
      end

      it "should close all IO handlers, except STDIN, STDOUT and STDERR" do
        GC.start
        command = [
          RUBY_CMD,
          File.expand_path(File.join(File.dirname(__FILE__), 'produce_status.rb')),
          EXIT_STATUS
        ]
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == EXIT_STATUS
        useless_handlers = 0
        ObjectSpace.each_object(IO) do |io|
          if ![STDIN, STDOUT, STDERR].include?(io)
            useless_handlers += 1 unless io.closed?
          end
        end
        useless_handlers.should == 0
      end

      it "should preserve the integrity of stdout when stderr is unavailable" do
        count = LARGE_OUTPUT_COUNTER
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stdout_only.rb'))}\" #{count}"
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0

        results = ''
        count.times do |i|
          results << "stdout #{i}\n"
        end
        status.output_text.should == results
        status.error_text.should == ''
        status.pid.should > 0
      end

      it "should preserve the integrity of stderr when stdout is unavailable" do
        count = LARGE_OUTPUT_COUNTER
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_stderr_only.rb'))}\" #{count}"
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0

        results = ''
        count.times do |i|
          results << "stderr #{i}\n"
        end
        status.error_text.should == results
        status.output_text.should == ''
        status.pid.should > 0
      end

      it "should preserve interleaved output when yielding CPU on consumer thread" do
        lines = 11
        exit_code = 42
        repeats = 5
        force_yield = 0.1
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_mixed_output.rb'))}\" #{lines} #{exit_code}"
        actual_output = StringIO.new
        actual_error = StringIO.new
        puts
        stats = runner.run_right_popen3(synchronicity, command, :repeats=>repeats, :force_yield=>force_yield) do |status|
          status.status.exitstatus.should == exit_code
          status.pid.should > 0
          actual_output << status.output_text
          actual_error << status.error_text
        end
        puts
        stats.size.should == repeats

        expected_output = StringIO.new
        repeats.times do
          lines.times do |i|
            expected_output << "stdout #{i}\n"
          end
        end
        actual_output.string.should == expected_output.string

        expected_error = StringIO.new
        repeats.times do
          lines.times do |i|
            (expected_error << "stderr #{i}\n") if 0 == i % 10
          end
        end
        actual_error.string.should == expected_error.string
      end

      it "should preserve interleaved output when process is spewing rapidly" do
        lines = LARGE_OUTPUT_COUNTER
        exit_code = 99
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_mixed_output.rb'))}\" #{lines} #{exit_code}"
        status = runner.run_right_popen3(synchronicity, command, :timeout=>10)
        status.status.exitstatus.should == exit_code

        expected_output = StringIO.new
        lines.times do |i|
          expected_output << "stdout #{i}\n"
        end
        status.output_text.should == expected_output.string

        expected_error = StringIO.new
        lines.times do |i|
          (expected_error << "stderr #{i}\n") if 0 == i % 10
        end
        status.error_text.should == expected_error.string
        status.pid.should > 0
      end

      it "should setup environment variables" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.output_text.should_not include('_test_')
        status = runner.run_right_popen3(synchronicity, command, :env=>{ :__test__ => '42' })
        status.status.exitstatus.should == 0
        status.output_text.should match(/^__test__=42$/)
        status.pid.should > 0
      end

      it "should restore environment variables" do
        begin
          ENV['__test__'] = '41'
          old_envs = {}
          ENV.each { |k, v| old_envs[k] = v }
          command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
          status = runner.run_right_popen3(synchronicity, command, :env=>{ :__test__ => '42' })
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
        it "should merge the PATH variable instead of overriding it" do
          command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'print_env.rb'))}\""
          status = runner.run_right_popen3(synchronicity, command, :env=>{ 'PATH' => "c:/bogus\\bin" })
          status.status.exitstatus.should == 0
          status.output_text.should include('c:\\bogus\\bin;')
          status.pid.should > 0
        end
      else
        it "should allow running bash command lines starting with a built-in command" do
          command = "for i in 1 2 3 4 5; do echo $i;done"
          status = runner.run_right_popen3(synchronicity, command)
          status.status.exitstatus.should == 0
          status.output_text.should == "1\n2\n3\n4\n5\n"
          status.pid.should > 0
        end

        it "should support running background processes" do
          command = "(sleep 20)&"
          now = Time.now
          status = runner.run_right_popen3(synchronicity, command)
          finished = Time.now
          (finished - now).should < 20
          status.did_timeout.should be_false
          status.status.exitstatus.should == 0
          status.output_text.should == ""
          status.pid.should > 0
        end
      end

      it "should support raw command arguments" do
        command = is_windows? ? ["cmd.exe", "/c", "echo", "*"] : ["echo", "*"]
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.output_text.should == "*\n"
        status.pid.should > 0
      end

      it "should run repeatedly without leaking resources" do
        pending 'Set environment variable TEST_LEAK to enable' unless ENV['TEST_LEAK']
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'produce_output.rb'))}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
        stats = runner.run_right_popen3(synchronicity, command, :repeats=>REPEAT_TEST_COUNTER)
        stats.each do |status|
          status.status.exitstatus.should == 0
          status.output_text.should == STANDARD_MESSAGE + "\n"
          status.error_text.should == ERROR_MESSAGE + "\n"
          status.pid.should > 0
        end
      end

      it "should pass input to child process" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'increment.rb'))}\""
        status = runner.run_right_popen3(synchronicity, command, :input=>"42\n")
        status.status.exitstatus.should == 0
        status.output_text.should == "43\n"
        status.error_text.should be_empty
        status.pid.should > 0
      end

      it "should run long child process without any watches by default" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'sleeper.rb'))}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :timeout=>nil)
        runner_status.status.exitstatus.should == 0
        runner_status.did_timeout.should be_false
        runner_status.output_text.should == "To sleep... 0\nTo sleep... 1\nTo sleep... 2\nTo sleep... 3\nThe sleeper must awaken.\n"
        runner_status.error_text.should == "Perchance to dream... 0\nPerchance to dream... 1\nPerchance to dream... 2\nPerchance to dream... 3\n"
      end

      it "should interrupt watched child process when timeout expires" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'sleeper.rb'))}\" 10"
        runner_status = runner.run_right_popen3(synchronicity, command, :expect_timeout=>true, :timeout=>0.1)
        runner_status.status.success?.should be_false
        runner_status.did_timeout.should be_true
        runner_status.output_text.should_not be_empty
        runner_status.error_text.should_not be_empty
      end

      it "should allow watched child to write files up to size limit" do
        ::Dir.mktmpdir do |watched_dir|
          command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'writer.rb'))}\" \"#{watched_dir}\""
          runner_status = runner.run_right_popen3(synchronicity, command, :size_limit_bytes=>1000, :watch_directory=>watched_dir, :timeout=>10)
          runner_status.status.success?.should be_true
          runner_status.did_size_limit.should be_false
        end
      end

      it "should interrupt watched child at size limit" do
        ::Dir.mktmpdir do |watched_dir|
          command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'writer.rb'))}\" \"#{watched_dir}\""
          runner_status = runner.run_right_popen3(synchronicity, command, :expect_size_limit=>true, :size_limit_bytes=>100, :watch_directory=>watched_dir, :timeout=>10)
          runner_status.status.success?.should be_false
          runner_status.did_size_limit.should be_true
        end
      end

      it "should handle child processes that close stdout but keep running" do
        pending 'not implemented for windows' if is_windows? && :sync != synchronicity
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'stdout.rb'))}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :expect_timeout=>true, :timeout=>2)
        runner_status.output_text.should be_empty
        runner_status.error_text.should == "Closing stdout\n"
        runner_status.did_timeout.should be_true
      end

      it "should handle child processes that spawn long running background processes" do
        pending 'not implemented for windows' if is_windows?
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'background.rb'))}\""
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.did_timeout.should be_false
        status.output_text.should be_empty
        status.error_text.should be_empty
      end

      it "should run long child process without any watches by default" do
        command = "\"#{RUBY_CMD}\" \"#{File.expand_path(File.join(File.dirname(__FILE__), 'sleeper.rb'))}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :timeout=>nil)
        runner_status.status.exitstatus.should == 0
        runner_status.did_timeout.should be_false
        runner_status.output_text.should == "To sleep... 0\nTo sleep... 1\nTo sleep... 2\nTo sleep... 3\nThe sleeper must awaken.\n"
        runner_status.error_text.should == "Perchance to dream... 0\nPerchance to dream... 1\nPerchance to dream... 2\nPerchance to dream... 3\n"
      end
    end
  end
end
