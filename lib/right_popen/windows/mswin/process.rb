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

require 'rubygems'
require 'win32/process'
require 'right_popen'
require 'right_popen/windows/windows_process_base'

require ::File.expand_path('../right_popen.so', __FILE__)  # mswin native code

module RightScale
  module RightPopen
    class Process < ::RightScale::RightPopen::WindowsProcessBase

      def initialize(*args)
        super
      end

      # Implements ProcessBase#alive?
      def alive?
        unless @pid
          raise ::RightScale::RightPopen::ProcessError, 'Process not started'
        end
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

      # Implements ProcessBase#wait_for_exit_status
      def wait_for_exit_status
        unless @pid
          raise ::RightScale::RightPopen::ProcessError, 'Process not started'
        end
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

      # Implements WindowsProcessBase#async_read
      def async_read(io)
        # use native implementation.
        ::RightScale::RightPopen.async_read(io)
      end

      protected

      # Implements WindowsProcessBase#popen4_impl
      def popen4_impl(cmd, environment_hash)
        # use native API call.
        environment_strings = ::RightScale::RightPopen::Windows::Utilities.environment_hash_to_string_block(environment_hash)
        ::RightScale::RightPopen.popen4(
          cmd,
          mode = 't',
          show_window = false,
          asynchronous_output = true,
          environment_strings)
      end

      # Implements WindowsProcessBase#current_user_environment_hash
      def current_user_environment_hash
        # use native API call.
        environment_strings = ::RightScale::RightPopen.get_current_user_environment
        ::RightScale::RightPopen::Windows::Utilities.string_block_to_environment_hash(environment_strings)
      end

      # Implements WindowsProcessBase#machine_environment_hash
      def machine_environment_hash
        # use native API call.
        environment_strings = ::RightScale::RightPopen.get_machine_environment
        ::RightScale::RightPopen::Windows::Utilities.string_block_to_environment_hash(environment_strings)
      end

    end
  end
end
