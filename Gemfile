source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'eventmachine', '~> 1.0.0.3'
end

group :development do
  gem 'rake',     '0.8.7'
  gem 'rspec',    '~> 1.3.1'
  gem 'flexmock', '~> 0.8.11'
end

group :windows do
  # TEAL NOTE: bundler cannot distinguish between mswin and mingw so when gems
  # are locked for the old mswin platform we have to guard it with
  # RUBY_PLATFORM. as far as bundler is concerned, mingw extends mswin and is
  # indistinguishable from it.
  if RUBY_PLATFORM =~ /mswin/
    platform :mswin do
      if ARGV == ['install']
        puts 'The generated Gemfile.lock is specific to mswin and should not be checked into source control.'
      end
      gem 'win32-api',     '1.4.5'
      gem 'windows-api',   '0.4.0'
      gem 'windows-pr',    '1.0.8'
      gem 'win32-dir',     '0.3.5'
      gem 'win32-process', '0.6.1'
      gem 'win32console',  '~> 1.3.0'
    end
  end
end
