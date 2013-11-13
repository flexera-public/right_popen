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

require 'rubygems'
require 'right_popen'

module RightScale::RightPopen
  module Windows
    module Utilities

      # 'immutable' key class for case-insensitive hash insertion/lookup.
      class NoCaseKey
        # Internal key
        attr_reader :key, :downcase_key

        # Stringizes object to be used as key
        def initialize(key)
          @key = key.to_s
          @downcase_key = @key.downcase
          @hashed = @downcase_key.hash
         end

        # Hash code
        def hash
          @hashed
        end

        # Equality for hash
        def eql?(other)
          @hashed == other.hash && @downcase_key == other.downcase_key
        end

        # Equality for array include?, etc.
        def ==(other)
          @hashed == other.hash && @downcase_key == other.downcase_key
        end

        # Sort operator
        def <=> other
          @downcase_key <=> other.downcase_key
        end

        # Stringizer
        def to_s
          @key
        end

        # Inspector
        def inspect
          "NoCaseKey: #{@key.inspect}"
        end
      end

      # blacklist to avoid merging some env vars that should never be changed by
      # the user or set explicitly for a child process. some are related to the
      # WoW64 environment and so the current process values may differ from what
      # is set in the system environment.
      BLACKLIST_MERGE_ENV_KEYS = %w[
        CommonProgramFiles CommonProgramFiles(x86) CommonProgramW6432
        ComSpec
        NUMBER_OF_PROCESSORS
        OS
        PROCESSOR_ARCHITECTURE PROCESSOR_IDENTIFIER
        PROCESSOR_LEVEL PROCESSOR_REVISION
        ProgramFiles ProgramFiles(x86) ProgramW6432
        PSModulePath
        TEMP TMP
        USERDOMAIN USERNAME USERPROFILE
        windir
      ].map { |k| NoCaseKey.new(k) }.freeze

      # Hash of known environment variable keys to special merge method proc.
      SPECIAL_MERGE_ENV_KEY_HASH = {
        NoCaseKey.new('PATH') => lambda { |from_value, to_value| merge_environment_path_value(from_value, to_value) }
      }

      # Merges the given environment hash with the current environment for this
      # process and the current environment for the current thread user from the
      # registry. The result is a nul-terminated block of nul-terminated strings
      # suitable for use in creating the child process.
      #
      # @param [Hash] environment_hash of environment key/value pairs or empty to only merge the current process and currend thread user environment.
      # @param [Hash] current_user_environment_hash from registry or empty
      # @param [Hash] machine_environment_hash from registry or empty
      #
      # @return [Hash] map of enviroment variable names(String) to either a value(String) or nil (to clear)
      def self.merge_environment(environment_hash,
                                 current_user_environment_hash,
                                 machine_environment_hash)

        # process environment has least precedence in this merging scheme.
        # use merge_environment2 to cheaply convert ENV keys to NoCaseKey.
        result_environment_hash = merge_environment2(::ENV, {})

        # machine from registry supercedes process.
        merge_environment2(
          machine_environment_hash,
          result_environment_hash,
          BLACKLIST_MERGE_ENV_KEYS)

        # user environment from registry supercedes machine and process. the
        # system account's (default user profile) registry values are not
        # appropriate for merging, so skip it when we know we are the system.
        current_user_name = (`whoami`.chomp rescue '')
        unless current_user_name == 'nt authority\system'
          merge_environment2(
            current_user_environment_hash,
            result_environment_hash,
            BLACKLIST_MERGE_ENV_KEYS)
        end

        # caller's environment supercedes all with no blacklisting.
        merge_environment2(environment_hash, result_environment_hash)

        # result map has ordinary strings as keys.
        return result_environment_hash.inject({}) do |result, (k, v)|
          result[k.to_s] = v
          result
        end
      end

      # Merges from hash to another with special handling for known env vars.
      #
      # @param [Hash] from_hash as source map of string or environment keys to environment values
      # @param [Hash] to_hash as target map of string or environment keys to environment values
      # @param [Array] blacklisted key names to avoid merging or empty
      #
      # @return [Hash] to_hash merged
      def self.merge_environment2(from_hash, to_hash, blacklisted = [])
        from_hash.each do |from_key, from_value|
          to_key = from_key.kind_of?(NoCaseKey) ?
                   from_key :
                   NoCaseKey.new(from_key)
          unless blacklisted.include?(to_key)
            # ensure from_value is string unless nil, which is used to clear.
            from_value = from_value.nil? ? nil : from_value.to_s
            to_value = to_hash[to_key]
            if to_value
              special_merge_proc = SPECIAL_MERGE_ENV_KEY_HASH[to_key]
              if special_merge_proc
                # special merge
                to_value = special_merge_proc.call(from_value, to_value)
              else
                # 'from' value supercedes existing 'to' value
                to_value = from_value
              end
            else
              # 'from' value replaces missing 'to' value
              to_value = from_value
            end
            to_hash[to_key] = to_value
          end
        end
        to_hash
      end

      # Merges a PATH-style variable by appending any missing subpaths on the
      # 'to' side to the value on the 'from' side in order of appearance. note
      # that the ordering of paths on the 'to' side is not preserved when some
      # of the paths also appear on the 'from' side. This is because paths on
      # the 'from' side always take precedence. This is an issue if two paths
      # reference similarly named executables and swapping the order of paths
      # would cause the wrong executable to be invoked. To resolve this, the
      # higher precedence path can be changed to ensure that the conflicting
      # paths are both specified in the proper order. There is no trivial
      # algorithm which can predict the proper ordering of such paths.
      #
      # @param [String] from_value to merge
      # @param [String] to_value to merge
      #
      # @return [String] merged value
      def self.merge_environment_path_value(from_value, to_value)
        # normalize to backslashes for Windows-style PATH variable.
        from_value = from_value.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
        to_value = to_value.gsub(File::SEPARATOR, File::ALT_SEPARATOR)

        # quick outs.
        return from_value if to_value.empty?
        return to_value if from_value.empty?

        # Windows paths are case-insensitive, so we want to match paths
        # efficiently while being case-insensitive. we will make use of
        # NoCaseKey again.
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

      # Converts a nul-terminated block of nul-terminated strings to a hash by
      # splitting the block on nul characters until the empty string is found.
      # splits substrings on the '=' character which is used to delimit key from
      # value in Windows environment blocks.
      #
      # @param [String] string_block as a string containing nul-terminated substrings followed by a nul-terminator.
      #
      # @return [Hash] map of environment key (String) to value (String)
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

          # note that Windows uses "=C:=C:\" notation for working directory
          # info; ignore equals if it is the first character.
          equals_offset = env_string.index('=', 1)
          if equals_offset
            env_key = env_string[0, equals_offset]
            env_value = env_string[equals_offset + 1..-1]
            result_hash[env_key] = env_value
          end
        end

        return result_hash
      end

      # Converts a hash of string to string to a string block by combining pairs
      # into a single string delimited by the '=' character and then placing
      # nul-terminators after each pair, followed by a final nul-terminator.
      #
      # @param [Hash] environment_hash to convert
      #
      # @return [String] environment string block
      def self.environment_hash_to_string_block(environment_hash)
        result_block = ''
        environment_hash.sort.each do |key, value|
          # omit nil values from the resulting string block; the child process
          # cannot inherit env vars from anywhere but our string block.
          result_block += "#{key}=#{value}\0" if value
        end
        result_block + "\0"
      end

    end # Utilities
  end # Windows
end # RightScale::RightPopen
