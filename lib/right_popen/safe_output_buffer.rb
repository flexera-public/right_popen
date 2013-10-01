#--
# Copyright (c) 2013 RightScale Inc
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

module RightScale

  module RightPopen

    # Provides an output handler implementation that buffers output (from a
    # child process) while ensuring that the output does not exhaust memory
    # in the current process. it does this by preserving only the most
    # interesting bits of data (start of lines, last in output).
    class SafeOutputBuffer

      # note utf-8 encodings for the Unicode elipsis character are inconsistent
      # between ruby platforms (Windows vs Linux) and versions (1.8 vs 1.9).
      ELLIPSIS = '...'

      DEFAULT_MAX_LINE_COUNT = 64
      DEFAULT_MAX_LINE_LENGTH = 256

      attr_reader :buffer, :max_line_count, :max_line_length

      # === Parameters
      # @param [Array] buffer for lines
      # @param [Integer] max_line_count to limit number of lines in buffer
      # @param [Integer] max_line_length to truncate charcters from start of line
      def initialize(buffer = [],
                     max_line_count = DEFAULT_MAX_LINE_COUNT,
                     max_line_length = DEFAULT_MAX_LINE_LENGTH)
        raise ArgumentError.new('buffer is required') unless @buffer = buffer
        raise ArgumentError.new('max_line_count is invalid') unless (@max_line_count = max_line_count) > 1
        raise ArgumentError.new('max_line_length is invalid') unless (@max_line_length = max_line_length) > ELLIPSIS.length
      end

      def display_text; @buffer.join("\n"); end

      # Buffers data with specified truncation.
      #
      # === Parameters
      # @param [Object] data of any kind
      def safe_buffer_data(data)
        # note that the chomping ensures that the exact output cannot be
        # preserved but the truncation would tend to eliminate trailing newlines
        # in any case. if you want exact output then don't use safe buffering.
        data = data.to_s.chomp
        if @buffer.size >= @max_line_count
          @buffer.shift
          @buffer[0] = ELLIPSIS
        end
        if data.length > @max_line_length
          truncation = [data.length - (@max_line_length - ELLIPSIS.length), 0].max
          data = "#{data[0..(@max_line_length - ELLIPSIS.length - 1)]}#{ELLIPSIS}"
        end
        @buffer << data
        true
      end
    end
  end
end
