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

require 'rubygems'
require 'eventmachine'
require 'win32/process'

require File.join(File.dirname(__FILE__), 'right_popen.so')  # win32 native code

module RightScale

  # Provides an eventmachine callback handler for the stdout stream.
  module StdOutHandler

    # Quacks like Process::Status, which we cannot instantiate ourselves because
    # has no public new method. RightScale::popen3 needs this because the
    # 'win32/process' gem currently won't return Process::Status objects but
    # only returns a [pid, exitstatus] value.
    class Status
      # Process ID
      attr_reader :pid

      # Process exit code
      attr_reader :exitstatus

      # === Parameters
      # pid(Integer):: Process ID.
      # 
      # exitstatus(Integer):: Process exit code
      def initialize(pid, exitstatus)
        @pid = pid
        @exitstatus = exitstatus
      end

      # Simulates Process::Status.exited?
      #
      # === Returns
      # true in all cases because this object cannot be returned until the
      # process exits
      def exited?
        return true
      end

      # Simulates Process::Status.success?
      #
      # === Returns
      # true if the process returned zero as its exit code
      def success?
        return @exitstatus ? (0 == @exitstatus) : true;
      end
    end

    # === Parameters
    # target(Object):: Object defining handler methods to be called.
    # stdout_handler(String):: Token for stdout handler method name.
    # exit_handler(String):: Token for exit handler method name.
    # stderr_eventable(Connector):: EM object representing stderr handler.
    # stream_out(IO):: Standard output stream.
    # pid(Integer):: Child process ID.
    def initialize(target, stdout_handler, exit_handler, stderr_eventable, stream_out, pid)
      @target = target
      @stdout_handler = stdout_handler
      @exit_handler = exit_handler
      @stderr_eventable = stderr_eventable
      @stream_out = stream_out
      @pid = pid
      @status = nil
    end

    # Callback from EM to asynchronously read the stdout stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8
    def notify_readable
      data = RightPopen.async_read(@stream_out)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @target.method(@stdout_handler).call(data) if @stdout_handler
    end

    # Override of Connection.get_status() for Windows implementation.
    def get_status
      unless @status
        begin
          @status = Status.new(@pid, Process.waitpid2(@pid)[1])
        rescue Process::Error
          # process is gone, which means we have no recourse to retrieve the
          # actual exit code; let's be optimistic.
          @status = Status.new(@pid, 0)
        end
      end
      return @status
    end

    # Callback from EM to unbind.
    def unbind
    # We force the stderr watched handler to go away so that
      # we don't end up with a broken pipe
      @stderr_eventable.force_detach if @stderr_eventable
      @target.method(@exit_handler).call(get_status) if @exit_handler
      @stream_out.close
    end
  end

  # Provides an eventmachine callback handler for the stderr stream.
  module StdErrHandler

    # === Parameters
    # target(Object):: Object defining handler methods to be called.
    #
    # stderr_handler(String):: Token for stderr handler method name.
    # 
    # stream_err(IO):: Standard error stream.
    def initialize(target, stderr_handler, stream_err)
      @target = target
      @stderr_handler = stderr_handler
      @stream_err = stream_err
      @unbound = false
    end

    # Callback from EM to asynchronously read the stderr stream. Note that this
    # callback mechanism is deprecated after EM v0.12.8
    def notify_readable
      data = RightPopen.async_read(@stream_err)
      receive_data(data) if (data && data.length > 0)
      detach unless data
    end

    # Callback from EM to receive data, which we also use to handle the
    # asynchronous data we read ourselves.
    def receive_data(data)
      @target.method(@stderr_handler).call(data)
    end

    # Callback from EM to unbind.
    def unbind
      @unbound = true
      @stream_err.close
    end

    # Forces detachment of the stderr handler on EM's next tick.
    def force_detach
      # Use next tick to prevent issue in EM where descriptors list
      # gets out-of-sync when calling detach in an unbind callback
      EM.next_tick { detach unless @unbound }
    end
  end

  # Creates a child process and connects event handlers to the standard output
  # and error streams used by the created process. Connectors use named pipes
  # and asynchronous I/O in the native Windows implementation.
  #
  # See RightScale.popen3
  def self.popen3_imp(options)
    raise "EventMachine reactor must be started" unless EM.reactor_running?

    # merge and format environment strings, if necessary.
    environment_hash = options[:environment] || {}
    environment_strings = RightPopenEx.merge_environment(environment_hash)

    # launch cmd and request asynchronous output.
    mode = "t"
    show_window = false
    asynchronous_output = true
    stream_in, stream_out, stream_err, pid = RightPopen.popen4(options[:command], mode, show_window, asynchronous_output, environment_strings)

    # close input immediately.
    stream_in.close

    # attach handlers to event machine and let it monitor incoming data. the
    # streams aren't used directly by the connectors except that they are closed
    # on unbind.
    stderr_eventable = EM.watch(stream_err, StdErrHandler, options[:target], options[:stderr_handler], stream_err) { |c| c.notify_readable = true } if options[:stderr_handler]
    EM.watch(stream_out, StdOutHandler, options[:target], options[:stdout_handler], options[:exit_handler], stderr_eventable, stream_out, pid) { |c| c.notify_readable = true }

    # note that control returns to the caller, but the launched cmd continues
    # running and sends output to the handlers. the caller is not responsible
    # for waiting for the process to terminate or closing streams as the
    # watched eventables will handle this automagically. notification will be
    # sent to the exit_handler on process termination.
  end

  protected

  module RightPopenEx
    # Key class for case-insensitive hash insertion/lookup.
    class NoCaseKey
      # Internal key
      attr_reader :key

      # Stringizes object to be used as key
      def initialize key
        @key = key.to_s
       end

      # Hash code
      def hash
        @key.downcase.hash
      end

      # Equality for hash
      def eql? other
        @key.downcase.hash == other.key.downcase.hash
      end

      # Sort operator
      def <=> other
        @key.downcase <=> other.key.downcase
      end

      # Stringizer
      def to_s
        @key
      end

      # Inspector
      def inspect
        "\"#{@key}\""
      end
    end

    # Hash of known environment variable keys to special merge method proc.
    SPECIAL_MERGE_ENV_KEY_HASH = {
      NoCaseKey.new('PATH') => lambda { |from_value, to_value| merge_environment_path_value(from_value, to_value) }
    }

    # Merges the given environment hash with the current environment for this
    # process and the current environment for the current thread user from the
    # registry. The result is a nul-terminated block of nul-terminated strings
    # suitable for use in creating the child process.
    #
    # === Parameters
    # environment_hash(Hash):: Hash of environment key/value pairs or empty to
    # only merge the current process and currend thread user environment.
    #
    # === Returns
    # merged string block
    def self.merge_environment(environment_hash)
      current_user_environment_hash = get_current_user_environment
      machine_environment_hash = get_machine_environment
      result_environment_hash = get_process_environment

      # machine from registry supercedes process.
      merge_environment2(machine_environment_hash, result_environment_hash)

      # user environment from registry supercedes machine and process.
      merge_environment2(current_user_environment_hash, result_environment_hash)

      # caller's environment supercedes all.
      merge_environment2(environment_hash, result_environment_hash)

      return environment_hash_to_string_block(result_environment_hash)
    end

    # Merges from hash to another with special handling for known env vars.
    #
    # === Parameters
    # from_hash(Hash):: hash of string or environment keys to environment values
    # to_hash(Hash):: resulting hash or environment keys to environment values
    #
    # === Returns
    # to_hash(Hash):: merged 'to' hash
    def self.merge_environment2(from_hash, to_hash)
      from_hash.each do |from_key, from_value|
        to_key = from_key.kind_of?(NoCaseKey) ?
                 from_key :
                 NoCaseKey.new(from_key)
        to_value = to_hash[to_key]
        if to_value
          special_merge_proc = SPECIAL_MERGE_ENV_KEY_HASH[to_key]
          if special_merge_proc
            # special merge
            to_hash[to_key] = special_merge_proc.call(from_value, to_value)
          else
            # 'from' value supercedes existing 'to' value
            to_hash[to_key] = from_value
          end
        else
          # 'from' value replaces missing 'to' value
          to_hash[to_key] = from_value
        end
      end
    end

    # Merges a PATH-style variable by appending any missing subpaths on the
    # 'to' side to the value on the 'from' side in order of appearance. note
    # that the ordering of paths on the 'to' side is not preserved when some of
    # the paths also appear on the 'from' side. This is because paths on the
    # 'from' side always take precedence. This is an issue if two paths
    # reference similarly named executables and swapping the order of paths
    # would cause the wrong executable to be invoked. To resolve this, the
    # higher precedence path can be changed to ensure that the conflicting paths
    # are both specified in the proper order. There is no trivial algorithm
    # which can predict the proper ordering of such paths.
    #
    # === Parameters
    # from_value(String):: value to merge from
    # to_value(String):: value to merge to
    #
    # === Returns
    # merged_value(String):: merged value
    def self.merge_environment_path_value(from_value, to_value)
      # normalize to backslashes for Windows-style PATH variable.
      from_value = from_value.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
      to_value = to_value.gsub(File::SEPARATOR, File::ALT_SEPARATOR)

      # quick outs.
      return from_value if to_value.empty?
      return to_value if from_value.empty?

      # Windows paths are case-insensitive, so we want to match paths efficiently
      # while being case-insensitive. we will make use of NoCaseKey again.
      from_value_hash = {}
      from_value.split(File::PATH_SEPARATOR).each { |path| from_value_hash[NoCaseKey.new(path)] = true }
      appender = ""
      to_value.split(File::PATH_SEPARATOR).each do |path|
        if not from_value_hash[NoCaseKey.new(path)]
          appender += File::PATH_SEPARATOR + path
        end
      end

      return from_value + appender
    end

    # Queries the environment strings from the current thread/process user's
    # environment. The resulting hash represents any variables set for the
    # persisted user context but any set dynamically in the current process
    # context.
    #
    # === Returns
    # environment_hash(Hash):: hash of environment key (String) to value (String).
    def self.get_current_user_environment
      environment_strings = RightPopen.get_current_user_environment

      return string_block_to_environment_hash(environment_strings)
    end

    # Queries the environment strings from the machine's environment.
    #
    # === Returns
    # environment_hash(Hash):: hash of environment key (String) to value (String).
    def self.get_machine_environment
      environment_strings = RightPopen.get_machine_environment

      return string_block_to_environment_hash(environment_strings)
    end

    # Queries the environment strings from the process environment (which is kept
    # in memory for each process and generally begins life as a copy of the
    # process user's environment context plus any changes made by ancestral
    # processes).
    #
    # === Returns
    # environment_hash(Hash):: hash of environment key (String) to value (String).
    def self.get_process_environment
      environment_strings = RightPopen.get_process_environment

      return string_block_to_environment_hash(environment_strings)
    end

    # Converts a nul-terminated block of nul-terminated strings to a hash by
    # splitting the block on nul characters until the empty string is found.
    # splits substrings on the '=' character which is used to delimit key from
    # value in Windows environment blocks.
    #
    # === Paramters
    # string_block(String):: string containing nul-terminated substrings followed
    # by a nul-terminator.
    #
    # === Returns
    # string_hash(Hash):: hash of string to string
    def self.string_block_to_environment_hash(string_block)
      result_hash = {}
      last_offset = 0
      string_block_length = string_block.length
      while last_offset < string_block_length
        offset = string_block.index(0.chr, last_offset)
        if offset.nil?
          offset = string_block.length
        end
        env_string = string_block[last_offset, offset - last_offset]
        break if env_string.empty?
        last_offset = offset + 1

        # note that Windows uses "=C:=C:\" notation for working directory info, so
        # ignore equals if it is the first character.
        equals_offset = env_string.index('=', 1)
        if equals_offset
          env_key = env_string[0, equals_offset]
          env_value = env_string[equals_offset + 1..-1]
          result_hash[NoCaseKey.new(env_key)] = env_value
        end
      end

      return result_hash
    end

    # Converts a hash of string to string to a string block by combining pairs
    # into a single string delimited by the '=' character and then placing nul-
    # terminators after each pair, followed by a final nul-terminator.
    #
    # === Parameters
    # environment_hash(Hash):: hash of
    def self.environment_hash_to_string_block(environment_hash)
      result_block = ""
      environment_hash.keys.sort.each do |key|
        result_block += "#{key}=#{environment_hash[key]}\0"
      end

      return result_block + "\0"
    end

  end
end
