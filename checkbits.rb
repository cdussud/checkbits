require 'digest'
require 'find'
require 'oj'

directory = ARGV.first
puts "Base directory is #{directory}"

def system_name?(path)
  File.basename(path)[0] == '.'
end

checksum_map = {}

# Recursive directory walk using the Find module
Find.find(directory) do |path|
  if File.directory?(path)
    Find.prune if system_name?(path)
  elsif !system_name?(path)
    checksum = Digest::SHA256.file(path).base64digest
    checksum_map[checksum] = [path, Time.now]
  end
end

json = Oj.dump(checksum_map)
File.open('checkbits.json', 'w') { |f| f.write(json) }
puts "Successfully wrote json file"