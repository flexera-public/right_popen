require 'rubygems'
require 'bundler'
require 'fileutils'
require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'spec/rake/spectask'
require 'rbconfig'

def list_spec_files
  list = Dir['spec/**/*_spec.rb']
  list.delete_if { |path| path.include?('/linux/') } if RUBY_PLATFORM =~ /mswin/
  list
end

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

    # remove v1.x binary directory.
    legacy_dir = 'lib/win32'
    ::FileUtils.rm_rf(legacy_dir) if ::File.directory?(legacy_dir)

    # remove current binary for mswin.
    binary_dir = 'lib/right_popen/windows/mswin'
    binary_path = ::File.join(binary_dir, 'right_popen.so')
    ::File.unlink(binary_path) if ::File.file?(binary_path)
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
    binary_dir = 'lib/right_popen/windows/mswin'
    mv 'ext/right_popen.so', binary_dir
  end
end

desc "Build a binary gem"
task :gem => [:build] do
  if RUBY_PLATFORM =~ /mswin/
    # the built .so file must appear under 'lib/.../mswin' for the windows gem
    # and the base gem task doesn't appear to handle this. this may be an issue
    # with calculating the file list in the gemspec before the .so has actually
    # been created. workaround is to invoke the gem build gemspec command line
    # after the build step produces the .so file.
    sh 'gem build right_popen.gemspec'
    FileUtils::rm_rf('pkg')
    FileUtils::mkdir_p('pkg')
    Dir.glob('*.gem').each { |gem_path| FileUtils::mv(gem_path, File.join('pkg', File.basename((gem_path)))) }
  end
end

desc 'Install the right_popen library as a gem'
task :install_gem => [:gem] do
  Dir.chdir(File.dirname(__FILE__)) do
     file = Dir["pkg/*.gem"].first
     sh "gem install #{file}"
  end
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
  t.spec_files = list_spec_files
end

desc "Run unit tests with RCov"
Spec::Rake::SpecTask.new(:rcov) do |t|
  t.spec_files = list_spec_files
  t.rcov = true
end

desc "Print Specdoc for unit tests"
Spec::Rake::SpecTask.new(:doc) do |t|
   t.spec_opts = ["--format", "specdoc", "--dry-run"]
   t.spec_files = list_spec_files
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
