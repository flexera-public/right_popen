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
require 'open3'
require 'win32/registry'
require 'right_popen'
require 'right_popen/windows/windows_process_base'

module RightScale
  module RightPopen
    class Process < ::RightScale::RightPopen::WindowsProcessBase

      def initialize(options={})
        super(options)
      end

      # Implements ProcessBase#alive?
      def alive?
        unless @wait_thread
          raise ::RightScale::RightPopen::ProcessError, 'Process not started'
        end
        unless @status
          # the wait thread is blocked on the child process handle so we only
          # need to ask if the thread is still alive.
          alive = @wait_thread.alive?
          wait_for_exit_status unless alive
        end
        @status.nil?
      end

      # Implements ProcessBase#wait_for_exit_status
      def wait_for_exit_status
        unless @wait_thread
          raise ::RightScale::RightPopen::ProcessError, 'Process not started'
        end
        unless @status
          # block on the thread until it dies (due to child process death).
          thread_status = @wait_thread.value

          # an interrupted process can still return zero exit status; if we
          # interrupted it then don't treat it as successful. simulate the Linux
          # termination signal behavior here.
          if interrupted?
            exitstatus = nil
            termsig    = @last_interrupt
          else
            # mingw follows the Linux semantic of masking off all but the low
            # word of the exitstatus while preserving the full exit code in the
            # .to_i value. Windows does not share the Linux semantic and
            # anything > 255 should be considered an error on Windows. the only
            # way to communicate this properly is to capture the real exit code
            # by down-shifting the thread_status.to_i value eight bits.
            exitstatus = thread_status.to_i >> 8
            termsig    = nil
          end
          @status = ::RightScale::RightPopen::ProcessStatus.new(
            @pid, exitstatus, termsig)
        end
        @status
      end

      # Implements WindowsProcessBase#async_read
      def async_read(io)
        # partial reads don't perform any translation on the bytes returned but
        # convert \r\n to \n for consistency with synchronous read behavior.
        # streaming child process stdout/stderr is intended to be text-only so
        # if the streamed data contains binary (which could contain ASCII x0D)
        # then it must be encoded using JSON or some other encapsulation layer.
        io.readpartial(4096).delete("\r")
      rescue ::EOFError
        nil
      end

      protected

      # Implements WindowsProcessBase#popen4_impl
      def popen4_impl(cmd, environment_hash)
        # use Open3 under mingw. Open3 will give us back a Thread object in the
        # fourth place, but this method only returns the PID for backward
        # compatibility with the mswin API.
        tuple = ::Open3.popen3(environment_hash, cmd).dup
        @wait_thread = tuple[3]
        tuple[3] = @wait_thread.pid
        tuple
      end

      # Implements WindowsProcessBase#current_user_environment_hash
      def current_user_environment_hash
        registry_key_to_environment_hash(
          ::Win32::Registry::HKEY_CURRENT_USER,
          'Environment')
      end

      # Implements WindowsProcessBase#machine_environment_hash
      def machine_environment_hash
        registry_key_to_environment_hash(
          ::Win32::Registry::HKEY_LOCAL_MACHINE,
          'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
      end

      # Uses the built-in registry classes to enumerate a registry key and
      # convert registry values to an environment variable hash.
      #
      # @param [Win32::Registry] base_key to enumerate
      # @param [String] sub_key_path to enumerate
      #
      # @return [Hash] map of environment names(String) to values(String)
      def registry_key_to_environment_hash(base_key, sub_key_path)
        result = {}
        begin
          base_key.open(sub_key_path) do |reg_key|
            reg_key.each_value do |name, type, data|
              case type
              when ::Win32::Registry::REG_EXPAND_SZ
                # some env var values refer to other env vars and need to be
                # 'expanded' to supply the missing fields. this is done in the
                # context of the current process environment.
                data = ::Win32::Registry.expand_environ(data)
              end
              result[name] = data
            end
          end
        rescue ::Win32::Registry::Error
          # ignored
        end
        result
      end

    end
  end
end
