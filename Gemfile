source 'https://rubygems.org'

unless RUBY_PLATFORM =~ /mswin/

  gem "eventmachine", ">=1.0.0.2" ,:git => "git@github.com:rightscale/rightscale-eventmachine.git"

  gemspec

else
  # both right_popen and EM are native extensions and require MSVC6 to build but,
  # even if MSVC6 is available on the PATH, bundler is unable to deal with just-in-time
  # compiling of MSVC6 gems. the only way to handle this to use a pre-built EM and to not
  # include the current source for right_popen.
  #
  # the following are meant to be a starter kit and not the complete bundle for the mswin
  # case. you will have to manage gems the old fashioned way so it recommended to start
  # with a clean 'ruby/lib/ruby/gems' directory, then 'gem install bundler', 'bundle install'.
  #
  # you must invoke 'rake gem' to build the gem and then 'rake spec' should work but
  # you should not use 'bundle exec'. the caveat is that you need to be on the
  # VCVARS command line so run (on 32-bit OS):
  #   "C:\Windows\system32\cmd.exe /k "C:\Program Files\Microsoft Visual Studio\VC98\Bin\VCVARS32.BAT"
  # or the equivalent (on 64-bit OS):
  #   "C:\Windows\SysWOW64\cmd.exe /k "C:\Program Files\Microsoft Visual Studio\VC98\Bin\VCVARS32.BAT"

  source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'

  gem "rake",           "0.8.7"
  gem "eventmachine",   "1.0.0.2"
  gem "rspec",          "~> 1.3"
  gem "flexmock",       "~> 0.8"
  gem "win32-api",      "1.4.5"
  gem "windows-api",    "0.4.0"
  gem "windows-pr",     "1.0.8"
  gem "win32-dir",      "0.3.5"
  gem "win32-process",  "0.6.1"
  gem "win32console",   "~> 1.3.0"
end
