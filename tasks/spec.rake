#--
# Copyright: Copyright (c) 2016 RightScale, Inc.
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

require 'rspec/core/rake_task'

# rake tasks are cumulative; two definitions of task means both get run.
# remove any previous definition of 'spec' task.
::Rake.application.instance_variable_get(:@tasks).delete('spec')

module Service
  module Task
    module Spec
      # define module once
    end
  end
end

module Service::Task::Spec

  RSPEC_CONFIG_FILE_NAME = '.rspec'

  # @return [Task] declared 'spec' task for running all specs
  def self.declare_task
    require 'rspec/core/rake_task'
    require 'right_develop/ci'

    # note that the do-block for the RakeTask initializer is only called when
    # the arity matches the expected task_args. that appears to have changed
    # between versions of rspec v2 so you cannot rely on that block being
    # called (i.e. it is silently not called for wrong arity). instead of that
    # we set the options after constructing the task.
    task = ::RSpec::Core::RakeTask.new(:spec)

    # honor .rspec when it appears in working directory or HOME path.
    # otherwise, we have a better set of defaults than rspec.
    case ::ENV['RACK_ENV'].to_s
    when '', 'development'
      configure_for_development(task)
    else
      # note that production and staging will raise for the require statement(s)
      # above because test gems are not installed.
      configure_for_integration(task)
    end
    task
  rescue ::LoadError => e
    puts "Skipping spec tasks due to missing gem(s): #{e.message}" if ['development', 'test'].include?(ENV['RACK_ENV'])
  end

  # @return [Task] spec tasks configured for development spec run
  def self.configure_for_development(task)
    current_config = RSPEC_CONFIG_FILE_NAME
    home_config = ::File.join(::ENV['HOME'].to_s, RSPEC_CONFIG_FILE_NAME)
    if ::File.file?(current_config)
      puts "NOTE: Using RSpec configuration at #{current_config.inspect}"
    elsif ::File.file?(home_config)
      puts "NOTE: Using RSpec configuration at #{home_config.inspect}"
    else
      # note the default task pattern is sufficient for recursively finding all
      # *_spec.rb files under working directory.
      task.rspec_opts = ['--color', '--format documentation', '--backtrace']
    end
    task
  end

  # @return [Task] spec tasks configured for continuous integration spec run
  def self.configure_for_integration(task)
    # note these options are borrowed from RightDevelop::CI::RakeTask
    task.rspec_opts = [
      '-r', 'right_develop/ci',
      '-f', 'RightDevelop::CI::RSpecFormatter',
      '-o', File.join('measurement', 'rspec', 'rspec.xml')
    ]
    task
  end

end # Service::Task::Spec

::Service::Task::Spec.declare_task
