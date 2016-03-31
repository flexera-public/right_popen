require 'rubygems'
require 'bundler/setup'

# legacy rspec depends on Test::Unit, which fails rspec runs that have any non-
# Test::Unit arguments. disable this nonsense.
require 'test/unit'
module ::Test::Unit::Options
  def process_args(args = [])
    {}
  end
end

require 'flexmock'
require 'rspec'
require 'right_popen'

RUBY_CMD         = 'ruby'
STANDARD_MESSAGE = 'Standard message'
ERROR_MESSAGE    = 'Error message'
EXIT_STATUS      = 146

# manually bump count up for more aggressive multi-processor testing, lessen
# for a quick smoke test
LARGE_OUTPUT_COUNTER = 1000

# bump up count for most exhaustive leak detection.
REPEAT_TEST_COUNTER = 256

module RightScale::RightPopen
  module SpecHelper
    def self.windows?
      !!(RUBY_PLATFORM =~ /mswin|win32|dos|mingw|cygwin/)
    end
  end
end

Spec::Runner.configure do |config|
  config.mock_with :flexmock
end
