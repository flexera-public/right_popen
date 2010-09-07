#--
# Copyright (c) 2009 RightScale Inc
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

# RightScale.popen3 allows running external processes aynchronously
# while still capturing their standard and error outputs.
# It relies on EventMachine for most of its internal mechanisms.

require 'rubygems'
require 'eventmachine'
require 'tempfile'

module RightScale

  # Provides an eventmachine callback handler for the stdout stream.
  module StdOutHandler

    # === Parameters
    # options[:input](String):: Input to be sent to child process stdin
    # options[:target](Object):: Object defining handler methods to be called.
    # options[:stdout_handler(String):: Token for stdout handler method name.
    # options[:exit_handler(String):: Token for exit handler method name.
    # options[:exec_file](String):: Path to executed file
    # stderr_eventable(Connector):: EM object representing stderr handler.
    # read_fd(IO):: Standard output read file descriptor.
    # write_fd(IO):: Standard output write file descriptor.
    def initialize(options, stderr_eventable, read_fd, write_fd)
      @input = options[:input]
      @target = options[:target]
      @stdout_handler = options[:stdout_handler]
      @exit_handler = options[:exit_handler]
      @exec_file = options[:exec_file]
      @stderr_eventable = stderr_eventable
      # Just so they don't get GCed before the process goes away
      @read_fd = read_fd
      @write_fd = write_fd
    end

    # Send input to child process stdin
    def post_init
      send_data(@input) if @input
    end

    # Callback from EM to receive data.
    def receive_data(data)
      @target.method(@stdout_handler).call(data) if @stdout_handler
    end

    # Callback from EM to unbind.
    def unbind
      # We force the attached stderr handler to go away so that
      # we don't end up with a broken pipe
      File.delete(@exec_file) if File.file?(@exec_file)
      @stderr_eventable.force_detach if @stderr_eventable
      @target.method(@exit_handler).call(get_status) if @exit_handler
    end
  end

  module StdErrHandler

    # === Parameters
    # target(Object):: Object defining handler methods to be called.
    #
    # stderr_handler(String):: Token for stderr handler method name.
    # read_fd(IO):: Error output read file descriptor.
    def initialize(target, stderr_handler, read_fd)
      @target = target
      @stderr_handler = stderr_handler
      @unbound = false
      @read_fd = read_fd # So it doesn't get GCed
    end

    # Callback from EM to receive data.
    def receive_data(data)
      @target.method(@stderr_handler).call(data)
    end

    # Callback from EM to unbind.
    def unbind
      @unbound = true
    end

    # Forces detachment of the stderr handler on EM's next tick.
    def force_detach
      # Use next tick to prevent issue in EM where descriptors list
      # gets out-of-sync when calling detach in an unbind callback
      EM.next_tick { detach unless @unbound }
    end
  end

  # Forks process to run given command asynchronously, hooking all three
  # standard streams of the child process.
  #
  # === Parameters
  # options[:pid_handler](Symbol):: Token for pid handler method name.
  # options[:temp_dir]:: Path to temporary directory where executable files are
  #                      created, default to /tmp if not specified
  #
  # See RightScale.popen3
  def self.popen3_imp(options)
    # First write command to file so that it's possible to use popen3 with
    # a bash command line (e.g. 'for i in 1 2 3 4 5; ...')
    exec_file = Tempfile.new('exec', options[:temp_dir] || Dir.tmpdir)
    options[:exec_file] = exec_file.path
    exec_file.puts(options[:command])
    exec_file.close
    File.chmod(0700, exec_file.path)
    GC.start # To garbage collect open file descriptors from passed executions
    EM.next_tick do
      saved_stderr = $stderr.dup
      r, w = Socket::pair(Socket::AF_LOCAL, Socket::SOCK_STREAM, 0)#IO::pipe

      $stderr.reopen w
      c = EM.attach(r, StdErrHandler, options[:target], options[:stderr_handler], r) if options[:stderr_handler]

      # Setup environment for child process
      envs = {}
      options[:environment].each { |k, v| envs[k.to_s] = v } if options[:environment]
      unless envs.empty?
        old_envs = {}
        ENV.each { |k, v| old_envs[k] = v if envs.include?(k) }
        envs.each { |k, v| ENV[k] = v }
      end

      # Launch child process
      connection = EM.popen(options[:exec_file], StdOutHandler, options, c, r, w)
      pid = EM.get_subprocess_pid(connection.signature)
      if options[:pid_handler]
        options[:target].method(options[:pid_handler]).call(pid)
      end

      wait_timer = EM::PeriodicTimer.new(1) do
        status = Process.waitpid(pid, Process::WNOHANG)
        unless status.nil?
          wait_timer.cancel
          options[:target].method(options[:exit_handler]).call(status) if options[:exit_handler]
        end
      end

      # Restore environment variables
      unless envs.empty?
        envs.each { |k, _| ENV[k] = nil }
        old_envs.each { |k, v| ENV[k] = v }
      end

      # Do not close 'w', strange things happen otherwise
      # (command protocol socket gets closed during decommission)
      $stderr.reopen saved_stderr
    end
    true
  end

end
