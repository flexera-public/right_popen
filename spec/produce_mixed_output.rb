count = ARGV[0] ? ARGV[0].to_i : 1

count.times do |i|
  $stderr.puts "stderr #{i}" if 0 == i % 10
  $stdout.puts "stdout #{i}"
end

exit 99
