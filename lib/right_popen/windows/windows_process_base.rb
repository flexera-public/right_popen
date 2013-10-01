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
require 'right_popen'
require 'right_popen/process_base'
require 'right_popen/windows/utilities'

module RightScale
  module RightPopen
    class WindowsProcessBase < ::RightScale::RightPopen::ProcessBase

      def initialize(*args)
        super
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
        environment_hash = ::RightScale::Windows::Utilities.merge_environment(
          environment_hash,
          current_user_environment_hash,
          machine_environment_hash)

        # resolve command string from array, if necessary.
        if cmd.kind_of?(::Array)
          escaped = []
          cmd.flatten.each_with_index do |token, token_index|
            token = token.to_s
            if token_index == 0
              token = self.class.find_executable_in_path(token)
            end
            escaped << self.class.quoted_command_token(token)
          end
          cmd = escaped.join(' ')
        else
          # resolve first token as an executable using PATH, etc.
          cmd = cmd.to_s
          delimiter = (cmd[0..0] == '"') ? '"' : ' '
          if delimiter_offset = cmd.index(delimiter, 1)
            token = cmd[0..delimiter_offset].strip
            remainder = cmd[(delimiter_offset + 1)..-1].to_s.strip
          else
            token = cmd
            remainder = ''
          end
          token = self.class.find_executable_in_path(token)
          token = self.class.quoted_command_token(token)
          if remainder.empty?
            cmd = token
          else
            cmd = "#{token} #{remainder}"
          end
        end

        result = []
        spawner = lambda do
          # launch cmd using native implementation.
          result += popen4_impl(cmd, environment_hash)
        end
        if @options[:directory]
          # note that invoking Dir.chdir with a block when already inside a
          # chdir block is can print an annoying warning to STDERR when paths
          # differ under circumstances that are hard to define.
          # case sensitivity? forward vs. backslash?
          # anyway, do our own comparison to try and avoid this warning.
          current_directory = ::Dir.pwd.gsub("\\", '/')
          new_directory = ::File.expand_path(@options[:directory]).gsub("\\", '/')
          if 0 == current_directory.casecmp(new_directory)
            spawner.call
          else
            ::Dir.chdir(@options[:directory]) { spawner.call }
          end
        else
          spawner.call
        end
        @stdin, @stdout, @stderr, @pid = result
        start_timer
        true
      rescue
        # catch-all for failure to spawn process ensuring a non-nil status. the
        # PID most likely is nil but the exit handler can be invoked for async.
        safe_close_io
        @status ||= ::RightScale::RightPopen::ProcessStatus.new(@pid, 1)
        raise
      end

      # Performs an asynchronous (non-blocking) read on the given I/O object.
      #
      # @param [IO] io to read
      #
      # @return [String] bytes read or empty to try again or nil to indicate EOF
      def async_read(io)
        raise NotImplementedError, 'Must be overridden'
      end

      # Finds the given command name in the PATH. this emulates the 'which'
      # command from linux (without the terminating newline). Supplies the
      # executable file extension if missing.
      #
      # === Parameters
      # @param [String] token to be qualified
      #
      # === Return
      # @return [String] path to first matching executable file in PATH or nil
      def self.find_executable_in_path(token)
        # strip any surrounding double-quotes (single quotes are considered to
        # be literals in Windows).
        token = unquoted_command_token(token)
        unless token.empty?
          # note that File.executable? returns a false positive in Windows for
          # directory paths, so only use File.file?
          return executable_path(token) if File.file?(token)

          # must search all known (executable) path extensions unless the
          # explicit extension was given. this handles a case such as 'curl'
          # which can either be on the path as 'curl.exe' or as a command shell
          # shortcut called 'curl.cmd', etc.
          use_path_extensions = 0 == File.extname(token).length
          path_extensions = use_path_extensions ? (ENV['PATHEXT'] || '').split(/;/) : nil

          # must check the current working directory first just to be completely
          # sure what would happen if the command were executed. note that Linux
          # ignores the CWD, so this is platform-specific behavior for Windows.
          cwd = Dir.getwd
          path = ENV['PATH']
          path = (path.nil? || 0 == path.length) ? cwd : (cwd + ';' + path)
          path.split(/;/).each do |dir|
            # note that PATH elements are optionally double-quoted.
            dir = unquoted_command_token(dir)
            if use_path_extensions
              path_extensions.each do |path_extension|
                path = File.join(dir, token + path_extension)
                return executable_path(path) if File.file?(path)
              end
            else
              path = File.join(dir, token)
              return executable_path(path) if File.file?(path)
            end
          end
        end

        # cannot be resolved.
        return nil
      end

      # Determines if the given command token requires double-quotes.
      #
      # === Parameter
      # @param [String] token
      #
      # === Return
      # @return [String] quoted token or unchanged
      def self.quoted_command_token(token)
        token = "\"#{token}\"" if token[0..0] != '"' && token.index(' ')
        token
      end

      # Determines if the given command token has double-quotes that need to be
      # removed.
      #
      # === Parameter
      # @param [String] token
      #
      # === Return
      # @return [String] unquoted token or unchanged
      def self.unquoted_command_token(token)
        delimiter = '"'
        if token[0..0] == delimiter
          delimiter_offset = token.index(delimiter, delimiter.length)
          if delimiter_offset
            token = token[1..(delimiter_offset-1)].strip
          else
            token = token[1..-1].strip
          end
        end
        token
      end

      # Makes a pretty path for executing a command in Windows.
      #
      # === Parameters
      # @param [String] path to qualify
      #
      # === Return
      # @return [String] fully qualified executable path
      def self.executable_path(path)
        ::File.expand_path(path).gsub('/', "\\")
      end

      protected

      # spawns a child process and returns I/O and process identifier (PID).
      #
      # @param [String] cmd to execute
      # @param [Hash] environment_hash for child process environment
      #
      # @return [Array] tuple of [stdin,stdout,stderr,pid]
      def popen4_impl(cmd, environment_hash)
        raise NotImplementedError, 'Must be overridden'
      end

      # Queries the environment strings from the current thread/process user's
      # environment. The resulting hash represents any variables set for the
      # persisted user context but any set dynamically in the current process
      # context.
      #
      # @return [Hash] map of environment key (String) to value (String)
      def current_user_environment_hash
        raise NotImplementedError, 'Must be overridden'
      end

      # Queries the environment strings from the machine's environment.
      #
      # @return [Hash] map of environment key (String) to value (String)
      def machine_environment_hash
        raise NotImplementedError, 'Must be overridden'
      end
    end
  end
end
