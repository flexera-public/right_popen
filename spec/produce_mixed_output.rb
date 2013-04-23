count = ARGV[0] ? ARGV[0].to_i : 1
exit_code = ARGV[1] ? ARGV[1].to_i : 0

STDOUT.sync=true
STDERR.sync=true

count.times do |i|
  $stderr.puts "stderr #{i}" if 0 == i % 10
  $stdout.puts "stdout #{i}"
end

exit exit_code
