require 'digest'
require 'find'
require 'oj'

CHECKSUM_FILE = 'checkbits.json'
BACKUP_FILE = CHECKSUM_FILE + '.backup'
MAX_FILE_SIZE = 30_000_000 # 30MB

# 
# Computes checksums for all files in a directory tree and
# writes to a json file
#

def system_name?(path)
  File.basename(path)[0] == '.'
end

directory = ARGV.first
puts "Base directory is #{directory}"

# Load checksum file
begin
  previous_json = File.open(CHECKSUM_FILE, 'r') { |f| f.read }
  File.rename(CHECKSUM_FILE, BACKUP_FILE)
  checksum_map = Oj.load(previous_json)
rescue => e
  checksum_map = {}
end

new_checksums = {}
changed_files = []

begin
  # Recursive directory walk using the Find module
  Find.find(directory) do |path|

    if File.directory?(path)
      Find.prune if system_name?(path) # skip directories starting with .
    elsif !system_name?(path)
      size = File.size(path)
      display_name = path[directory.length + 1..-1]

      if size > MAX_FILE_SIZE
        puts "Skipping large file (#{size.to_f / 1e6} MB): #{display_name}"
        next
      end

      checksum = Digest::SHA256.file(path).base64digest
      entry = checksum_map[path]
      if entry != nil
        if checksum == entry[0]
          puts "Verified #{display_name}" 
        else
          # TODO: last known good
          puts "[ERROR] checksum changed: #{display_name}"
          changed_files << path
        end
      else
        puts "Adding new file #{display_name}"
      end

      # TODO: if a checksum failed should we really save the new one?
      new_checksums[path] = [checksum, Time.now]
    end
  end

  # Write out new file. This is how we prune out deleted or moved files
  json = Oj.dump(new_checksums)
  File.open(CHECKSUM_FILE, 'w') { |f| f.write(json) }
  File.delete(BACKUP_FILE)
  puts "Successfully wrote json file"
rescue Interrupt
  puts "Exiting early!"
rescue => e
  puts e.message
ensure
  if changed_files.any?
    puts "All changed files"
    puts changed_file
  end
end


# TODO
# Next up
#  - for each file compare the checksum to the precomputed one
#   - if it differs raise a warning and output last known good time
#  - be able to do partial checks of the whold directory