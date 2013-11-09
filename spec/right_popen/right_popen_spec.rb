require ::File.expand_path('../../spec_helper', __FILE__)
require ::File.expand_path('../../runner', __FILE__)

require 'stringio'
require 'tmpdir'

describe RightScale::RightPopen do
  def windows?
    ::RightScale::RightPopen::SpecHelper.windows?
  end

  def script_path_for(name)
    name += '.rb' if ::File.extname(name).empty?
    ::File.expand_path(::File.join(::File.dirname(__FILE__), 'scripts', name))
  end

  let(:runner) { ::RightScale::RightPopen::Runner.new }

  it "should correctly handle many small processes [async]" do
    pending 'Set environment variable TEST_STRESS to enable' unless ENV['TEST_STRESS']
    run_count = 100
    command = windows? ? ['cmd.exe', '/c', 'exit 0'] : ['sh', '-c', 'exit 0']
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_output')}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
        runner_status = runner.run_right_popen3(synchronicity, command)
        runner_status.should_not be_nil
        runner_status.status.should_not be_nil
        runner_status.status.exitstatus.should == 0
        runner_status.output_text.should == STANDARD_MESSAGE + "\n"
        runner_status.error_text.should == ERROR_MESSAGE + "\n"
        runner_status.pid.should > 0
      end

      it "should return the right status" do
        ruby = ::RbConfig.respond_to?(:ruby) ?
          ::RbConfig.ruby :
          `which ruby`.chomp  # 'which' on Windows is a custom RS utility similar to 'where' but better ;)
        command = [
          ruby,
          script_path_for('produce_status'),
          EXIT_STATUS
        ]
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == EXIT_STATUS
        status.output_text.should == ''
        status.error_text.should == ''
        status.pid.should > 0
      end

      if ::RightScale::RightPopen::SpecHelper.windows?
        it "should return the right status for Windows" do
          # Windows does not adhere to the Linux semantic of masking off any
          # exit code value above the low word. it is important that the real
          # exit code be relayed via exitstatus on Windows only.
          high_word_exit_code = 3 * 256
          command = "cmd.exe /c exit #{high_word_exit_code}"
          status = runner.run_right_popen3(synchronicity, command)
          status.status.exitstatus.should == high_word_exit_code
          status.status.success?.should be_false
          status.output_text.should == ''
          status.error_text.should == ''
          status.pid.should > 0
        end
      end

      it "should close all IO handlers, except STDIN, STDOUT and STDERR" do
        GC.start
        command = [
          RUBY_CMD,
          script_path_for('produce_status'),
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_stdout_only')}\" #{count}"
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_stderr_only')}\" #{count}"
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_mixed_output')}\" #{lines} #{exit_code}"
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_mixed_output')}\" #{lines} #{exit_code}"
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
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('print_env')}\""
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.output_text.should_not include('_test_')
        status = runner.run_right_popen3(synchronicity, command, :env=>{ :__test__ => '42' })
        status.status.exitstatus.should == 0
        status.output_text.should match(/^__test__=42$/)
        status.pid.should > 0
      end

      it 'should handle non-string environment variables' do
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('print_env')}\""
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.output_text.should_not include('_test_')
        status = runner.run_right_popen3(synchronicity, command, :env=>{ :__test__ => false })
        status.status.exitstatus.should == 0
        status.output_text.should match(/^__test__=false$/)
        status.pid.should > 0
      end

      it "should clear environment variables" do
        begin
          ENV['__test__'] = '42'
          old_envs = {}
          ENV.each { |k, v| old_envs[k] = v }
          command = "\"#{RUBY_CMD}\" \"#{script_path_for('print_env')}\""
          status = runner.run_right_popen3(synchronicity, command, :env=>{ :__test__ => nil })
          status.status.exitstatus.should == 0
          status.output_text.should include('PATH')
          status.output_text.should_not include('_test_')
          ENV.each { |k, v| old_envs[k].should == v }
          old_envs.each { |k, v| ENV[k].should == v }
          status.pid.should > 0
        ensure
          ENV.delete('__test__')
        end
      end

      it "should restore environment variables" do
        begin
          ENV['__test__'] = '41'
          old_envs = {}
          ENV.each { |k, v| old_envs[k] = v }
          command = "\"#{RUBY_CMD}\" \"#{script_path_for('print_env')}\""
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

      if ::RightScale::RightPopen::SpecHelper.windows?
        # FIX: this behavior is currently specific to Windows but should probably be
        # implemented for Linux.
        it "should merge the PATH variable instead of overriding it" do
          command = "\"#{RUBY_CMD}\" \"#{script_path_for('print_env')}\""
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
        command = windows? ? ["cmd.exe", "/c", "echo", "*"] : ["echo", "*"]
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.output_text.should == "*\n"
        status.pid.should > 0
      end

      it "should run repeatedly without leaking resources" do
        pending 'Set environment variable TEST_LEAK to enable' unless ENV['TEST_LEAK']
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('produce_output')}\" \"#{STANDARD_MESSAGE}\" \"#{ERROR_MESSAGE}\""
        stats = runner.run_right_popen3(synchronicity, command, :repeats=>REPEAT_TEST_COUNTER)
        stats.each do |status|
          status.status.exitstatus.should == 0
          status.output_text.should == STANDARD_MESSAGE + "\n"
          status.error_text.should == ERROR_MESSAGE + "\n"
          status.pid.should > 0
        end
      end

      it "should pass input to child process" do
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('increment')}\""
        status = runner.run_right_popen3(synchronicity, command, :input=>"42\n")
        status.status.exitstatus.should == 0
        status.output_text.should == "43\n"
        status.error_text.should be_empty
        status.pid.should > 0
      end

      it "should run long child process without any watches by default" do
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('sleeper')}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :timeout=>nil)
        runner_status.status.exitstatus.should == 0
        runner_status.did_timeout.should be_false
        runner_status.output_text.should == "To sleep... 0\nTo sleep... 1\nTo sleep... 2\nTo sleep... 3\nThe sleeper must awaken.\n"
        runner_status.error_text.should == "Perchance to dream... 0\nPerchance to dream... 1\nPerchance to dream... 2\nPerchance to dream... 3\n"
      end

      it "should interrupt watched child process when timeout expires" do
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('sleeper')}\" 10"
        runner_status = runner.run_right_popen3(synchronicity, command, :expect_timeout=>true, :timeout=>0.1)
        runner_status.status.success?.should be_false
        runner_status.did_timeout.should be_true
        runner_status.output_text.should_not be_empty
        runner_status.error_text.should_not be_empty
      end

      it "should allow watched child to write files up to size limit" do
        ::Dir.mktmpdir do |watched_dir|
          command = "\"#{RUBY_CMD}\" \"#{script_path_for('writer')}\" \"#{watched_dir}\""
          runner_status = runner.run_right_popen3(synchronicity, command, :size_limit_bytes=>1000, :watch_directory=>watched_dir, :timeout=>10)
          runner_status.status.success?.should be_true
          runner_status.did_size_limit.should be_false
        end
      end

      it "should interrupt watched child at size limit" do
        ::Dir.mktmpdir do |watched_dir|
          command = "\"#{RUBY_CMD}\" \"#{script_path_for('writer')}\" \"#{watched_dir}\""
          runner_status = runner.run_right_popen3(synchronicity, command, :expect_size_limit=>true, :size_limit_bytes=>100, :watch_directory=>watched_dir, :timeout=>10)
          runner_status.status.success?.should be_false
          runner_status.did_size_limit.should be_true
        end
      end

      it "should handle child processes that close stdout but keep running" do
        pending 'not implemented for windows' if windows? && :sync != synchronicity
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('stdout')}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :expect_timeout=>true, :timeout=>2)
        runner_status.output_text.should be_empty
        runner_status.error_text.should =~ /Closing stdout\n/
        runner_status.did_timeout.should be_true
      end

      it "should handle child processes that spawn long running background processes" do
        pending 'not implemented for windows' if windows?
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('background')}\""
        status = runner.run_right_popen3(synchronicity, command)
        status.status.exitstatus.should == 0
        status.did_timeout.should be_false
        status.output_text.should be_empty
        status.error_text.should be_empty
      end

      it "should run long child process without any watches by default" do
        command = "\"#{RUBY_CMD}\" \"#{script_path_for('sleeper')}\""
        runner_status = runner.run_right_popen3(synchronicity, command, :timeout=>nil)
        runner_status.status.exitstatus.should == 0
        runner_status.did_timeout.should be_false
        runner_status.output_text.should == "To sleep... 0\nTo sleep... 1\nTo sleep... 2\nTo sleep... 3\nThe sleeper must awaken.\n"
        runner_status.error_text.should == "Perchance to dream... 0\nPerchance to dream... 1\nPerchance to dream... 2\nPerchance to dream... 3\n"
      end

      it 'should fail to run as missing user' do
        command = windows? ? ['cmd.exe', '/c', 'whoami'] : ['whoami']
        trial = lambda { runner.run_right_popen3(synchronicity, command, :user => 'nosuchuser') }
        if windows?
          expect(&trial).to raise_exception(::NotImplementedError)
        else
          expect(&trial).to raise_exception(::RightScale::RightPopen::ProcessError, /nosuchuser/)
        end

        # TEAL FIX: difficult to create a positive test without sudo privileges
        # or mocking out the relevant behavior.
      end

      it 'should raise ENOENT for invalid executables' do
        command = 'nosuchexecutable'
        expect{ runner.run_right_popen3(synchronicity, [command]) }.
          to raise_exception(::RightScale::RightPopen::ProcessError, /nosuchexecutable/)
      end

    end # synchronicity
  end # each synchronicity
end # RightScale::RightPopen
