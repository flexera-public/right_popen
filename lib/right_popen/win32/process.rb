#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2013 RightScale, Inc.
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

require 'win32/process'

require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'process_base'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'process_status'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), 'right_popen_ex'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', '..', 'win32', 'right_popen.so'))  # win32 native code

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
          # note that ::Process.kill(0, pid) is unreliable from win32-process
          # gem because it can returns a false positive if called before and
          # then after process termination.
          handle = ::Windows::Process::OpenProcess.call(
            desired_access = ::Windows::Process::PROCESS_ALL_ACCESS,
            inherit_handle = 0,
            @pid)
          alive = false
          if handle != ::Windows::Handle::INVALID_HANDLE_VALUE
            begin
              # immediate check (zero milliseconds) to see if process handle is
              # signalled (i.e. terminated). the process remains signalled after
              # termination and can be checked repeatedly in this manner (until
              # the OS recycles the PID at an unspecified time later).
              result = ::Windows::Synchronize::WaitForSingleObject.call(
                handle,
                milliseconds = 0)
              alive = result == ::Windows::Synchronize::WAIT_TIMEOUT
            ensure
              ::Windows::Handle::CloseHandle.call(handle)
            end
          end
          wait_for_exit_status unless alive
        end
        @status.nil?
      end

      # Windows must drain all streams on child death in order to ensure all
      # output is read. if the child closes only one of the streams there is no
      # possibility of hanging (Windows will simply read EOF).
      #
      # === Return
      # @return [TrueClass|FalseClass] true if draining all
      def drain_all_upon_death?
        true
      end

      # @return [Array] escalating termination signals for this platform
      def signals_for_interrupt
        ['INT', 'BRK', 'KILL']
      end

      # spawns a child process using given command and handler target in a
      # win32-specific manner.
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

        # garbage collection has no good effect for spawning a child process in
        # Windows because forking is not supported and so Ruby objects cannot be
        # shared with child process (although handles can be shared via some
        # advanced API programming). the following GC call is only for
        # compatibility with the Linux implementation.
        ::GC.start

        # merge and format environment strings, if necessary.
        environment_hash = @options[:environment] || {}
        environment_strings = ::RightScale::RightPopenEx.merge_environment(environment_hash)

        # resolve command string from array, if necessary.
        if cmd.kind_of?(::Array)
          escaped = []
          cmd.flatten.each do |arg|
            value = arg.to_s
            escaped << (value.index(' ') ? "\"#{value}\"" : value)
          end
          cmd = escaped.join(' ')
        end

        # avoid calling Dir.chdir unless necessary because it prints annoying
        # warnings on reentrance even when directory is same.
        if new_directory = @options[:directory]
          old_directory = ::File.expand_path(::Dir.pwd).gsub("\\", '/')
          new_directory = ::File.expand_path(new_directory).gsub("\\", '/')
          # do nothing if new directory is same as old directory
          if new_directory == old_directory
            new_directory = nil
            old_directory = nil
          else
            # child process will inherit parent's working directory on creation.
            ::Dir.chdir(new_directory)
          end
        else
          old_directory = nil
        end

        begin
          # launch cmd using native win32 implementation.
          @stdin, @stdout, @stderr, @pid = ::RightScale::RightPopen.popen4(
            cmd,
            mode = 't',
            show_window = false,
            asynchronous_output = true,
            environment_strings)
        ensure
          ::Dir.chdir(old_directory) if old_directory
        end
        start_timer
        true
      rescue
        # catch-all for failure to spawn process ensuring a non-nil status. the
        # PID most likely is nil but the exit handler can be invoked for async.
        safe_close_io
        @status = ::RightScale::RightPopen::ProcessStatus.new(@pid, 1)
        raise
      end

      # blocks waiting for process exit status.
      #
      # === Return
      # @return [ProcessStatus] exit status
      def wait_for_exit_status
        raise ProcessError.new('Process not started') unless @pid
        unless @status
          exitstatus = 0
          begin
            # note that win32-process gem doesn't support the no-hang parameter
            # and returns exit code instead of status.
            ignored, exitstatus = ::Process.waitpid2(@pid)
          rescue Process::Error
            # process is gone, which means we have no recourse to retrieve the
            # actual exit code.
          end

          # an interrupted process can still return zero exit status; if we
          # interrupted it then don't treat it as successful. simulate the Linux
          # termination signal behavior here.
          if interrupted?
            exitstatus = nil
            termsig = @last_interrupt
          end
          @status = ::RightScale::RightPopen::ProcessStatus.new(@pid, exitstatus, termsig)
        end
        @status
      end

    end
  end
end
