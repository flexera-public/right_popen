if RUBY_PLATFORM =~ /mswin/
  require 'mkmf'

  create_makefile('right_popen', 'mswin')
end
