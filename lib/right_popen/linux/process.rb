#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011-2013 RightScale, Inc.
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

require 'etc'

require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'process_base'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'process_status'))

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
        raise ProcessError.new('Process not started') unless @pid
        unless @status
          begin
            ignored, status = ::Process.waitpid2(@pid, ::Process::WNOHANG)
            @status = status
          rescue
            wait_for_exit_status
          end
        end
        @status.nil?
      end

      # blocks waiting for process exit status.
      #
      # === Return
      # @return [ProcessStatus] exit status
      def wait_for_exit_status
        raise ProcessError.new('Process not started') unless @pid
        unless @status
          begin
            ignored, status = ::Process.waitpid2(@pid)
            @status = status
          rescue
            # ignored
          end
        end

        # an interrupted process can have a nil exitstatus; create a new status
        # in this case so caller can always expect an integer exitstatus.
        if @status.nil? || @status.exitstatus.nil?
          exitstatus = interrupted? ? 1 : 0
          @status = ::RightScale::RightPopen::ProcessStatus.new(pid, exitstatus)
        end
        @status
      end

      # spawns (forks) a child process using given command and handler target in
      # linux-specific manner.
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

        # garbage collect any open file descriptors from past executions before
        # forking to prevent them being inherited. also reduces memory footprint
        # since forking will duplicate everything in memory for child process.
        ::GC.start

        # create pipes.
        stdin_r, stdin_w = IO.pipe
        stdout_r, stdout_w = IO.pipe
        stderr_r, stderr_w = IO.pipe
        status_r, status_w = IO.pipe

        [stdin_r, stdin_w, stdout_r, stdout_w,
         stderr_r, stderr_w, status_r, status_w].each {|fdes| fdes.sync = true}

        @pid = ::Kernel::fork do
          begin
            stdin_w.close
            ::STDIN.reopen stdin_r

            stdout_r.close
            ::STDOUT.reopen stdout_w

            stderr_r.close
            ::STDERR.reopen stderr_w

            status_r.close
            status_w.fcntl(::Fcntl::F_SETFD, ::Fcntl::FD_CLOEXEC)

            unless @options[:inherit_io]
              ::ObjectSpace.each_object(IO) do |io|
                if ![::STDIN, ::STDOUT, ::STDERR, status_w].include?(io)
                  io.close unless io.closed?
                end
              end
            end

            if group = get_group
              ::Process.egid = group
              ::Process.gid = group
            end

            if user = get_user
              ::Process.euid = user
              ::Process.uid = user
            end

            if umask = get_umask
              ::File.umask(umask)
            end

            ::Dir.chdir(@options[:directory]) if @options[:directory]

            environment_hash = {}.merge(@options[:environment] || {})
            environment_hash['LC_ALL'] = 'C' if @options[:locale]
            environment_hash.each { |key, value| ::ENV[key.to_s] = value.to_s }

            if cmd.kind_of?(Array)
              cmd = cmd.map { |c| c.to_s } #exec only likes string arguments
              exec(*cmd)
            else
              exec('sh', '-c', cmd.to_s)  # allows shell commands for cmd string
            end
            raise 'Unreachable code'
          rescue ::Exception => e
            ::Marshal.dump(e, status_w)
          end
          status_w.close
          exit!
        end

        stdin_r.close
        stdout_w.close
        stderr_w.close
        status_w.close
        @stdin = stdin_w
        @stdout = stdout_r
        @stderr = stderr_r
        @status_fd = status_r
        true
      end

      # Interrupts the running process (without abandoning watch) in increasing
      # degrees of signalled severity.
      #
      # === Return
      # @return [TrueClass|FalseClass] true if process was alive and killed, false if dead
      def interrupt
        while alive?
          if !@kill_time || Time.now >= @kill_time
            @next_kill_signal ||= 'INT'
            if @next_kill_signal == :abandon_child
              raise ::RightScale::RightPopen::ProcessError.new("Unable to kill child process")
            end
            # Process.kill returns 1 for success or else raises an exception
            result = ::Process.kill(@next_kill_signal, @pid) rescue nil

            # soft then hard interrupt (assumed to be called periodically until
            # process is gone).
            case @next_kill_signal
            when 'INT'
              @next_kill_signal = 'TERM'
              @kill_time = Time.now + 3 # seconds for interrupt before term
            when 'TERM'
              @next_kill_signal = 'KILL'
              @kill_time = Time.now + 3 # more seconds for term before kill
            else
              # there will be no more kill attempts; abandon child next time
              @next_kill_signal = :abandon_child
              @kill_time = Time.now + 3 # more seconds until abandoning child
            end
            if result
              @interrupted = true  # short circuit any outer state machine to retry interrupt
              break
            else
              # last kill attempt disallowed; go around again with escalation.
              @kill_time = nil
            end
          end
        end
        @interrupted
      end

      # @deprecated this seems like test harness code smell, not production code.
      def wait_for_exec
        warn 'WARNING: RightScale::RightPopen::Process#wait_for_exec is deprecated in lib and will be moved to spec'
        begin
          e = ::Marshal.load(@status_fd)
          # thus meaning that the process failed to exec...
          @stdin.close
          @stdout.close
          @stderr.close
          raise(Exception === e ? e : "unknown failure!")
        rescue EOFError
          # thus meaning that the process did exec and we can continue.
        ensure
          @status_fd.close
        end
      end

      private

      def get_user
        if user = @options[:user]
          user = Etc.getpwnam(user).uid unless user.kind_of?(Integer)
        end
        user
      end

      def get_group
        if group = @options[:group]
          group = Etc.getgrnam(group).gid unless group.kind_of?(Integer)
        end
        group
      end

      def get_umask
        if umask = @options[:umask]
          if umask.respond_to?(:oct)
            umask = umask.oct
          else
            umask = umask.to_i
          end
          umask = umask & 007777
        end
        umask
      end
    end
  end
end
