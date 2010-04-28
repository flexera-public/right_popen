require 'rubygems'
require 'fileutils'
require 'rake'
require 'rake/clean'
require 'rake/testtask'
require 'rbconfig'

include Config

desc "Clean any build files for right_popen"
task :clean do
  if RUBY_PLATFORM =~ /mswin/
    if File.exists?('ext/Makefile')
      Dir.chdir('ext') do
        sh 'nmake distclean'
      end
    end
    rm 'lib/win32/right_popen.so' if File.file?('lib/win32/right_popen.so')
  end
end

desc "Build right_popen (but don't install it)"
task :build => [:clean] do
  if RUBY_PLATFORM =~ /mswin/
    Dir.chdir('ext') do
      ruby 'extconf.rb'
      sh 'nmake'
    end
    FileUtils::mkdir_p 'lib/win32'
    mv 'ext/right_popen.so', 'lib/win32'
  end
end

desc "Build a binary gem"
task :gem => [:build] do
   Dir["*.gem"].each { |gem| rm gem }
   ruby 'right_popen.gemspec'
end

desc 'Install the right_popen library as a gem'
task :install_gem => [:gem] do
   file = Dir["*.gem"].first
   sh "gem install #{file}"
end

desc 'Uninstalls and reinstalls the right_popen library as a gem'
task :reinstall_gem do
   sh "gem uninstall right_popen"
   sh "rake install_gem"
end

desc 'Runs all spec tests'
task :spec do
  sh "spec spec/*_spec.rb"
end
