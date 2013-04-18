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

module RightScale

  module RightPopen

    # Quacks like Process::Status, which we cannot instantiate ourselves because
    # has no public new method for cases where we need to create our own.
    class ProcessStatus

      attr_reader :pid, :exitstatus, :termsig

      # === Parameters
      # @param [Integer] pid as process identifier
      # @param [Integer] exitstatus as process exit code or nil
      # @param [Integer] termination signal or nil
      def initialize(pid, exitstatus, termsig=nil)
        @pid = pid
        @exitstatus = exitstatus
        @termsig = termsig
      end

      # Simulates Process::Status.exited? which seems like a weird method since
      # this object cannot logically be queried until the process exits.
      #
      # === Returns
      # @return [TrueClass] always true
      def exited?
        return true
      end

      # Simulates Process::Status.success?
      #
      # === Returns
      # true if the process returned zero as its exit code or nil if terminate was signalled
      def success?
        # note that Linux ruby returns nil when exitstatus is nil and a termsig
        # value is set instead.
        return @exitstatus ? (0 == @exitstatus) : nil
      end
    end
  end
end
