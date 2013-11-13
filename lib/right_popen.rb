#--
# Copyright (c) 2009-2013 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

module RightScale
  module RightPopen

    # exceptions
    class ProcessError < Exception; end

    # autoloads
    autoload :ProcessStatus, 'right_popen/process_status'
    autoload :SafeOutputBuffer, 'right_popen/safe_output_buffer'
    autoload :TargetProxy, 'right_popen/target_proxy'

    # see popen3_async for details.
    DEFAULT_POPEN3_OPTIONS = {
      :directory        => nil,
      :environment      => nil,
      :exit_handler     => nil,
      :group            => nil,
      :inherit_io       => false,
      :input            => nil,
      :locale           => true,
      :pid_handler      => nil,
      :size_limit_bytes => nil,
      :stderr_handler   => nil,
      :stdout_handler   => nil,
      :target           => nil,
      :timeout_seconds  => nil,
      :umask            => nil,
      :user             => nil,
      :watch_handler    => nil,
      :watch_directory  => nil,
    }

    # Loads the specified implementation.
    #
    # === Parameters
    # @param [Symbol|String] synchronicity to load
    #
    # === Return
    # @return [TrueClass] always true
    def self.require_popen3_impl(synchronicity)
      # implementation of Process is specific to platform.
      case RUBY_PLATFORM
      when /mswin/
        platform_subdir = 'windows'
        impl_subdir = ::File.join(platform_subdir, 'mswin')
      when /mingw/
        platform_subdir = 'windows'
        impl_subdir = ::File.join(platform_subdir, 'mingw')
      when /win32|dos|cygwin/
        raise NotImplementedError
      else
        platform_subdir = 'linux'
        impl_subdir = platform_subdir
      end
      impl_module = ::File.join(impl_subdir, 'process')

      # only require EM when async is requested.
      case synchronicity
      when :popen3_sync
        sync_module = 'popen3_sync'
      when :popen3_async
        sync_module = ::File.join(platform_subdir, 'popen3_async')
      else
        fail 'unexpected synchronicity'
      end

      # platform-specific requires.
      base_dir = ::File.join(::File.dirname(__FILE__), 'right_popen').gsub("\\", '/')
      require ::File.expand_path(impl_module, base_dir)
      require ::File.expand_path(sync_module, base_dir)
    end

    # Spawns a process to run given command synchronously. This is similar to
    # the Ruby backtick but also supports streaming I/O, process watching, etc.
    # Does not require any evented library to use.
    #
    # Streams the command's stdout and stderr to the given handlers. Time-
    # ordering of bytes sent to stdout and stderr is not preserved.
    #
    # Calls given exit handler upon command process termination, passing in the
    # resulting Process::Status.
    #
    # All handlers must be methods exposed by the given target.
    #
    # === Parameters
    # @param [Hash] options see popen3_async for details
    #
    # === Returns
    # @return [TrueClass] always true
    def self.popen3_sync(cmd, options)
      options = DEFAULT_POPEN3_OPTIONS.dup.merge(options)
      require_popen3_impl(:popen3_sync)
      ::RightScale::RightPopen.popen3_sync_impl(
        cmd, ::RightScale::RightPopen::TargetProxy.new(options), options)
    end

    # Spawns a process to run given command asynchronously, hooking all three
    # standard streams of the child process. Implementation requires the
    # eventmachine gem.
    #
    # Streams the command's stdout and stderr to the given handlers. Time-
    # ordering of bytes sent to stdout and stderr is not preserved.
    #
    # Calls given exit handler upon command process termination, passing in the
    # resulting Process::Status.
    #
    # All handlers must be methods exposed by the given target.
    #
    # === Parameters
    # @param [Hash] options for execution
    # @option options [String] :directory as initial working directory for child process or nil to inherit current working directory
    # @option options [Hash] :environment variables values keyed by name
    # @option options [Symbol] :exit_handler target method called on exit
    # @option options [Integer|String] :group or gid for forked process (linux only)
    # @option options [TrueClass|FalseClass] :inherit_io set to true to share all IO objects with forked process or false to close shared IO objects (default) (linux only)
    # @option options [String] :input string that will get streamed into child's process stdin
    # @option options [TrueClass|FalseClass] :locale set to true to export LC_ALL=C in the forked environment (default) or false to use default locale (linux only)
    # @option options [Symbol] :pid_handler target method called with process ID (PID)
    # @option options [Integer] :size_limit_bytes for total size of watched directory after which child process will be interrupted
    # @option options [Symbol] :stderr_handler target method called as error text is received
    # @option options [Symbol] :stdout_handler target method called as output text is received
    # @option options [Object] :target object defining handler methods to be called (no handlers can be defined if not specified)
    # @option options [Numeric] :timeout_seconds after which child process will be interrupted
    # @option options [Integer|String] :umask for files created by process (linux only)
    # @option options [Integer|String] :user or uid for forked process (linux only)
    # @option options [Symbol] :watch_handler called periodically with process during watch; return true to continue, false to abandon (sync only)
    # @option options [String] :watch_directory to monitor for child process writing files
    # @option options [Symbol] :async_exception_handler target method called if an exception is handled (on another thread)
    #
    # === Returns
    # @return [TrueClass] always true
    def self.popen3_async(cmd, options)
      options = DEFAULT_POPEN3_OPTIONS.dup.merge(options)
      require_popen3_impl(:popen3_async)
      unless ::EM.reactor_running?
        raise ::ArgumentError, "EventMachine reactor must be running."
      end
      ::RightScale::RightPopen.popen3_async_impl(
        cmd, ::RightScale::RightPopen::TargetProxy.new(options), options)
    end
  end
end
