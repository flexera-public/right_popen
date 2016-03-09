spec = ::Gem::Specification.new do |spec|
  platforms = [:linux, :mswin, :mingw]
  case RUBY_PLATFORM
  when /mswin/
    platform = :mswin
  when /mingw/
    if RUBY_VERSION =~ /^1\.9\.\d$/
      platform = :mingw
    else
      fail 'This gem is for use with ruby 1.9 mingw only.'
    end
  else
    platform = :linux
  end

  spec.name      = 'right_popen'
  spec.version   = '3.0.1'
  spec.authors   = ['Scott Messier', 'Raphael Simon', 'Tony Spataro']
  spec.email     = 'support@rightscale.com'
  spec.homepage  = 'https://github.com/rightscale/right_popen'
  case platform
  when :mswin
    spec.platform = 'x86-mswin32-60'
  when :mingw
    spec.platform = 'x86-mingw32'
  else
    spec.platform  = Gem::Platform::RUBY
  end
  spec.summary = 'Provides a platform-independent popen implementation'
  spec.has_rdoc = true
  spec.rdoc_options = ["--main", "README.rdoc", "--title", "RightPopen"]
  spec.extra_rdoc_files = ["README.rdoc"]
  spec.required_ruby_version = '>= 1.9.3'
  spec.rubyforge_project = %q{right_popen}

  spec.description = <<-EOF
RightPopen allows running external processes aynchronously while still
capturing their standard and error outputs. It relies on EventMachine for the
asynchronous popen call but EM is not required for synchronous popen.
The Linux implementation is valid for any Linux platform but there is also a
native implementation for Windows platforms.
EOF

  case platform
  when :mswin
    extension_dir = 'ext,'
  else
    extension_dir = ''
  end
  candidates = ::Dir.glob("{#{extension_dir}lib}/**/*") +
               %w(LICENSE README.rdoc right_popen.gemspec)
  exclusions = [
    'Makefile', '.obj', '.pdb', '.def', '.exp', '.lib',
    'win32/right_popen.so'  # original .so directory, now mswin
  ]
  candidates = candidates.delete_if do |item|
    exclusions.any? { |exclusion| item.include?(exclusion) }
  end

  # remove files specific to other platforms.
  case platform
  when :mswin
    candidates = candidates.delete_if { |item| item.include?('/linux/') }
    candidates = candidates.delete_if { |item| item.include?('/mingw/') }
  when :mingw
    candidates = candidates.delete_if { |item| item.include?('/linux/') }
    candidates = candidates.delete_if { |item| item.include?('/mswin/') }
  else
    candidates = candidates.delete_if { |item| item.include?('/windows/') }
  end
  spec.files = candidates.sort!

  # Current implementation supports >= 1.0.0
  spec.add_development_dependency(%q<eventmachine>, [">= 1.0.0"])
  case platform
  when :mswin
    spec.add_runtime_dependency('win32-api', '1.4.5')
    spec.add_runtime_dependency('windows-api', '0.4.0')
    spec.add_runtime_dependency('windows-pr', '1.0.8')
    spec.add_runtime_dependency('win32-dir', '0.3.5')
    spec.add_runtime_dependency('win32-process', '0.6.1')
    spec.add_development_dependency('win32console', '~> 1.3.0')
  end
end
