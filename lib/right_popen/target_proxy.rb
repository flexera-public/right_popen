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

    # proxies calls to target to simplify popen3 implementation code and to make
    # the proxied callbacks slightly more efficient.
    class TargetProxy

      HANDLER_NAME_TO_PARAMETER_COUNT = {
        :exit_handler       => 1,
        :pid_handler        => 1,
        :size_limit_handler => 0,
        :stderr_handler     => 1,
        :stdout_handler     => 1,
        :timeout_handler    => 0,
        :watch_handler      => 1,
      }

      def initialize(options = {})
        if options[:target].nil? &&
           !(options.keys & HANDLER_NAME_TO_PARAMETER_COUNT.keys).empty?
          raise ArgumentError, "Missing target"
        end
        @target = options[:target]  # hold target reference (if any) against GC

        # define an instance method for each handler that either proxies
        # directly to the target method (with parameters) or else does nothing.
        HANDLER_NAME_TO_PARAMETER_COUNT.each do |handler_name, parameter_count|
          parameter_list = (1..parameter_count).map { |i| "p#{i}" }.join(', ')
          instance_eval <<EOF
if @target && options[#{handler_name.inspect}]
  @#{handler_name.to_s}_method = @target.method(options[#{handler_name.inspect}])
  def #{handler_name.to_s}(#{parameter_list})
    @#{handler_name.to_s}_method.call(#{parameter_list})
  end
else
  def #{handler_name.to_s}(#{parameter_list}); true; end
end
EOF
          end
      end
    end

  end # RightPopen
end # RightScale
