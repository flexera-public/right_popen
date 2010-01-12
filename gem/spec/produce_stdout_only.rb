count = ARGV[0] ? ARGV[0].to_i : 1

count.times do |i|
  $stdout.puts "stdout #{i}"
end
