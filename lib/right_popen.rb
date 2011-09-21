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

if RUBY_PLATFORM =~ /mswin/
  require File.expand_path(File.join(File.dirname(__FILE__), 'right_popen', 'win32', 'right_popen'))
else
  require File.expand_path(File.join(File.dirname(__FILE__), 'right_popen', 'linux', 'right_popen'))
end

module RightScale

  # Spawn process to run given command asynchronously, hooking all three
  # standard streams of the child process.
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
  # options[:command](String or Array):: Command to execute, including any arguments as a single string or an array of command and arguments
  # options[:environment](Hash):: Hash of environment variables values keyed by name
  # options[:input](String):: Input string that will get streamed into child's process stdin
  # options[:target](Object):: object defining handler methods to be called, optional (no handlers can be defined if not specified)
  # options[:pid_handler](String):: PID notification handler method name, optional
  # options[:stdout_handler](String):: Stdout handler method name, optional
  # options[:stderr_handler](String):: Stderr handler method name, optional
  # options[:exit_handler](String):: Exit handler method name, optional
  #
  # === Returns
  # true:: always true
  def self.popen3(options)
    raise "EventMachine reactor must be started" unless EM.reactor_running?
    raise "Missing command" unless options[:command]
    raise "Missing target" unless options[:target] || !options[:stdout_handler] && !options[:stderr_handler] && !options[:exit_handler] && !options[:pid_handler]
    return RightScale.popen3_imp(options)
  end

end
