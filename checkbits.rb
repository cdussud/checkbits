require 'digest'
require 'find'

sha256 = Digest::SHA256.file('checkbits.rb')
puts "My checksum is #{sha256.base64digest}"

directory = ARGV.first
puts "Base directory is #{directory}"


def system_name?(path)
  File.basename(path)[0] == '.'
end

# Recursive directory walk using the Find module
Find.find(directory) do |path|
  if File.directory?(path)
    Find.prune if system_name?(path)
  elsif !system_name?(path)
    puts path
    puts Digest::SHA256.file(path).base64digest
    puts "\n"
  end
end