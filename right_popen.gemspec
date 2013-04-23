$:.push File.expand_path("../lib", __FILE__)
require "right_popen/version"

spec = Gem::Specification.new do |spec|
  is_windows = RUBY_PLATFORM =~ /mswin/

  spec.name      = 'right_popen'
  spec.version   = RightScale::RightPopen::VERSION
  spec.authors   = ['Scott Messier', 'Raphael Simon', 'Graham Hughes']
  spec.email     = 'scott@rightscale.com'
  spec.homepage  = 'https://github.com/rightscale/right_popen'
  if is_windows
    spec.platform = 'x86-mswin32-60'
  else
    spec.platform  = Gem::Platform::RUBY
  end
  spec.summary   = 'Provides a platform-independent popen implementation'
  spec.has_rdoc = true
  spec.rdoc_options = ["--main", "README.rdoc", "--title", "RightPopen"]
  spec.extra_rdoc_files = ["README.rdoc"]
  spec.required_ruby_version = '>= 1.8.6'
  spec.rubyforge_project = %q{right_popen}

  spec.description = <<-EOF
RightPopen allows running external processes aynchronously while still
capturing their standard and error outputs. It relies on EventMachine for most
of its internal mechanisms. The Linux implementation is valid for any Linux
platform but there is also a native implementation for Windows platforms.
EOF

  if is_windows
    extension_dir = "ext,"
  else
    extension_dir = ""
  end
  candidates = Dir.glob("{#{extension_dir}lib,spec}/**/*") +
               ["LICENSE", "README.rdoc", "Rakefile", "right_popen.gemspec"]
  candidates = candidates.delete_if do |item|
    item.include?("Makefile") || item.include?(".obj") || item.include?(".pdb") || item.include?(".def") || item.include?(".exp") || item.include?(".lib")
  end
  candidates = candidates.delete_if do |item|
    if is_windows
      item.include?("/linux/")
    else
      item.include?("/win32/")
    end
  end
  spec.files = candidates.sort!

  # Current implementation supports >= 1.0.0
  spec.add_development_dependency(%q<eventmachine>, [">= 1.0.0"])
  if is_windows
    spec.add_runtime_dependency(%q<win32-process>, [">= 0.6.1"])
  end
  spec.add_development_dependency('rspec', "~> 1.3")
  spec.add_development_dependency('rake', "~> 0.8.7")
  spec.add_development_dependency('flexmock')
end
