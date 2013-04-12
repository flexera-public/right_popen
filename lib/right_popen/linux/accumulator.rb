#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
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

module RightScale
  module RightPopen

    # @deprecated this seems like test harness code smell, not production code
    class Accumulator
      READ_CHUNK_SIZE = 4096

      def initialize(process, inputs, read_callbacks, outputs, write_callbacks)
        warn 'WARNING: RightScale::RightPopen::Accumulator is deprecated in lib and will be moved to spec'
        @process = process
        @inputs = inputs
        @outputs = outputs
        null = Proc.new {}
        @reads = {}
        @writes = {}
        inputs.zip(read_callbacks).each do |pair|
          input, callback = pair
          @reads[input] = callback
        end
        outputs.zip(write_callbacks).each do |pair|
          output, callback = pair
          @writes[output] = callback
        end
        @writebuffers = {}
        @status = nil
      end

      def status
        unless @status
          @status = ::Process.waitpid2(@process.pid, ::Process::WNOHANG)
        end
        @status
      end

      def tick(sleep_time = 0.1)
        return true unless @status.nil?

        status

        inputs = @inputs.dup
        outputs = @outputs.dup
        ready = nil
        while ready.nil?
          begin
            # in theory, we should note "exceptional conditions" and
            # permit procs for those, too.  In practice there are only
            # two times when exceptional conditions occur: out of band
            # data in TCP connections and "packet mode" for
            # pseudoterminals.  We care about neither of these,
            # therefore ignore exceptional conditions.
            ready = IO.select(inputs, outputs, nil, sleep_time)
          rescue Errno::EAGAIN, Errno::EINTR
          end
        end unless inputs.empty? && outputs.empty?

        ready[0].each do |fdes|
          if fdes.eof?
            fdes.close
            @inputs.delete(fdes)
          else
            chunk = fdes.readpartial(READ_CHUNK_SIZE)
            @reads[fdes].call(chunk) if @reads[fdes]
          end
        end unless ready.nil? || ready[0].nil?
        ready[1].each do |fdes|
          buffered = @writebuffers[fdes]
          buffered = @writes[fdes].call if @writes[fdes] if buffered.nil? || buffered.empty?
          if buffered.nil?
            fdes.close
            @outputs.delete(fdes)
          elsif !buffered.empty?
            begin
              amount = fdes.write_nonblock buffered
              @writebuffers[fdes] = buffered[amount..-1]
            rescue Errno::EPIPE
              # subprocess closed the pipe; fine.
              fdes.close
              @outputs.delete(fdes)
            end
          end
        end unless ready.nil? || ready[1].nil?

        return !@status.nil?
      end

      def number_waiting_on
        @inputs.size + @outputs.size
      end

      def cleanup
        @inputs.each {|p| p.close unless p.closed? }
        @outputs.each {|p| p.close unless p.closed? }
        @status = ::Process.waitpid2(@process.pid) if @status.nil?
      end

      def run_to_completion(sleep_time=0.1)
        until tick(sleep_time)
          break if number_waiting_on == 0
        end
        cleanup
      end
    end
  end
end
