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

  # helper classes for the win32 implementation of RightPopen.
  #
  # TEAL FIX: can't rename this module until/unless our mixlib-shellout
  # implementation is changed to use our Process class instead of calling these
  # methods directly. even better would be to stop using a custom version of
  # mixlib-shellout.
  module RightPopenEx

    # @deprecated because it is not specific to win32 platform.
    class Status < ::RightScale::RightPopen::ProcessStatus

      def initialize(pid, exitstatus)
        super(pid, exitstatus)
        warn "WARNING: RightScale::RightPopenEx::Status is deprecated in favor of ::RightScale::RightPopen::ProcessStatus"
      end
    end

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

      # user environment from registry supercedes machine and process. the
      # system account's (default user profile) registry values are not
      # appropriate for merging, so skip it when we know we are the system.
      current_user_name = (`whoami`.chomp rescue '')
      merge_environment2(current_user_environment_hash, result_environment_hash) unless current_user_name == 'nt authority\system'

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
