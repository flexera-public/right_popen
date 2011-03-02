require 'rubygems'
require 'bundler'
require 'fileutils'
require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'spec/rake/spectask'
require 'rbconfig'

include Config

Bundler::GemHelper.install_tasks

# == Gem == #

gemtask = Rake::GemPackageTask.new(Gem::Specification.load("right_popen.gemspec")) do |package|
  package.package_dir = ENV['PACKAGE_DIR'] || 'pkg'
  package.need_zip = true
  package.need_tar = true
end

directory gemtask.package_dir

CLEAN.include(gemtask.package_dir)

desc "Clean any build files for right_popen"
task :win_clean do
  if RUBY_PLATFORM =~ /mswin/
    if File.exists?('ext/Makefile')
      Dir.chdir('ext') do
        sh 'nmake distclean'
      end
    end
    rm 'lib/win32/right_popen.so' if File.file?('lib/win32/right_popen.so')
  end
end
task :clean => :win_clean

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
task :gem => [:build]

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

# == Unit Tests == #

task :specs => :spec

desc "Run unit tests"
Spec::Rake::SpecTask.new do |t|
  t.spec_files = Dir['spec/**/*_spec.rb']
end

desc "Run unit tests with RCov"
Spec::Rake::SpecTask.new(:rcov) do |t|
  t.spec_files = Dir['spec/**/*_spec.rb']
  t.rcov = true
end

desc "Print Specdoc for unit tests"
Spec::Rake::SpecTask.new(:doc) do |t|
   t.spec_opts = ["--format", "specdoc", "--dry-run"]
   t.spec_files = Dir['spec/**/*_spec.rb']
end

# == Documentation == #

desc "Generate API documentation to doc/rdocs/index.html"
Rake::RDocTask.new do |rd|
  rd.rdoc_dir = 'doc/rdocs'
  rd.main = 'README.rdoc'
  rd.rdoc_files.include 'README.rdoc', "lib/**/*.rb"

  rd.options << '--inline-source'
  rd.options << '--line-numbers'
  rd.options << '--all'
  rd.options << '--fileboxes'
  rd.options << '--diagram'
end

# == Emacs integration == #
desc "Rebuild TAGS file"
task :tags do
  sh "rtags -R lib spec"
end
