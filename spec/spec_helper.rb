require 'rubygems'
require 'spec'
require 'eventmachine'
require File.join(File.dirname(__FILE__), '..', 'lib', 'right_popen')

RUBY_CMD         = 'ruby'
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

# manually bump count up for more aggressive multi-processor testing, lessen
# for a quick smoke test
LARGE_OUTPUT_COUNTER = 1000

# bump up count for most exhaustive leak detection.
REPEAT_TEST_COUNTER = 256

def is_windows?
  return RUBY_PLATFORM =~ /mswin/
end
