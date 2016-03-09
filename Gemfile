source 'https://rubygems.org'

gem 'eventmachine', '~> 1.0.8'

group :development do
  # Omit these from gemspec since many RubyGems versions are silly and install
  # development dependencies even when doing 'gem install'
  gem 'rake'
  gem 'rspec',    '~> 2.0'
  gem 'flexmock', '~> 0.9'

  gem 'right_develop'
end

group :debugger do
  gem 'pry'
  gem 'pry-byebug'
end

group :windows do
  # NOTE: bundler cannot distinguish between mswin and mingw so when gems
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
