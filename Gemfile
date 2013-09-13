source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org'

gemspec

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'eventmachine', '~> 1.0.0.3'
end

gem "json", "1.4.6"  # locked for mswin32 friendliness

group :windows do
  platform :mswin do
    gem 'win32-api',     '1.4.5'
    gem 'windows-api',   '0.4.0'
    gem 'windows-pr',    '1.0.8'
    gem 'win32-dir',     '0.3.5'
    gem 'win32-process', '0.6.1'
    gem 'win32console',  '~> 1.3.0'
  end
end

group :development do
  gem 'rake',     '0.8.7'
  gem 'rspec',    '~> 1.3'
  gem 'flexmock', '~> 0.8'
  platform :mswin do
    gem 'win32console', '~> 1.3.0'
  end
end
