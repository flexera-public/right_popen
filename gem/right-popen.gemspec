require 'rubygems'

spec = Gem::Specification.new do |spec|
  spec.name      = 'right-popen'
  spec.version   = '1.0.0'
  spec.authors   = ['Scott Messier', 'Raphael Simon']
  spec.email     = 'scott@rightscale.com'
  spec.homepage  = 'https://github.com/rightscale/right_popen'
  if RUBY_PLATFORM =~ /mswin/
    spec.platform = 'x86-mswin32-60'
  else
    spec.platform  = Gem::Platform::RUBY
  end
  spec.summary   = 'Provides a platform-independent popen implementation'
  spec.has_rdoc  = true
  spec.required_ruby_version = '>= 1.8.6'

  spec.description = <<-EOF
The right-popen provides a platform-independent implemetation of the
popen3 library. Ruby's built-in popen implementation only works under
Linux platforms and so additional gymnastics are provided here for
Windows. A common interface hides implementation details from the caller.
EOF

  if RUBY_PLATFORM =~ /mswin/
    extension_dir = "ext,"
  else
    extension_dir = ""
  end
  candidates = Dir.glob("{#{extension_dir}lib,spec}/**/*") +
               ["README", "Rakefile", "right-popen.gemspec"]
  spec.files = candidates.delete_if do |item|
    item.include?("Makefile") || item.include?(".obj") || item.include?(".pdb") || item.include?(".def") || item.include?(".exp") || item.include?(".lib")
  end
  spec.files.sort!
end

if $PROGRAM_NAME == __FILE__
   Gem.manage_gems if Gem::RubyGemsVersion.to_f < 1.0
   Gem::Builder.new(spec).build
end
