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

require File.expand_path(File.join(File.dirname(__FILE__), "process"))
require File.expand_path(File.join(File.dirname(__FILE__), "accumulator"))

module RightScale
  module RightPopen

    # @deprecated this seems like test harness code smell, not production code
    module Utilities
      module_function

      SIGNAL_LOOKUP = Signal.list.invert

      def reason(status)
        if status.exitstatus
          "with exit status #{status.exitstatus}"
        else
          "due to SIG#{SIGNAL_LOOKUP[status.termsig]}"
        end
      end
      private :reason
      
      def run(cmd, parameters={})
        status, out, err = run_collecting_output(cmd, parameters)
        unless status.success?
          raise "Command \"#{cmd}\" failed #{reason(status)}: " +
            "stdout #{out}, stderr #{err}"
        end
        [out, err]
      end

      def run_with_stdin_collecting_output(cmd, input, parameters={})
        out = StringIO.new
        err = StringIO.new
        first = true
        status = run_with_blocks(cmd,
                                 Proc.new {
                                   if (first)
                                     first = false
                                     input
                                   else
                                     nil
                                   end},
                                 Proc.new {|s| out.write(s)},
                                 Proc.new {|s| err.write(s)})
        [status, out.string, err.string]
      end
      alias_method :run_input, :run_with_stdin_collecting_output

      def run_collecting_output(cmd, parameters={})
        out = StringIO.new
        err = StringIO.new
        status = run_with_blocks(cmd, nil, Proc.new {|s| out.write(s)},
                                 Proc.new {|s| err.write(s)})
        [status, out.string, err.string]
      end
      alias_method :spawn, :run_collecting_output

      def run_with_blocks(cmd, stdin_block, stdout_block, stderr_block, parameters={})
        warn 'WARNING: RightScale::RightPopen::Utilities are deprecated in lib and will be moved to spec'
        process = Process.new(parameters)
        process.spawn(cmd, ::RightScale::RightPopen::TargetProxy.new(parameters))
        process.wait_for_exec
        a = Accumulator.new(process,
                            [process.stdout, process.stderr], [stdout_block, stderr_block],
                            [process.stdin], [stdin_block])
        a.run_to_completion
        a.status[1]
      end
    end
  end
end
