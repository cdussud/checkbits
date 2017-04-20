require 'digest'
require 'find'
require 'bundler'
Bundler.require

# TODO
# Next up
#  - output elapsed time

CHECKSUM_FILE = 'checkbits.json'
MAX_FILE_SIZE = 30_000_000 # 30MB

class ChecksumEntry
  attr_accessor :checksum
  attr_accessor :file_modified_at
  attr_accessor :verified_at

  def initialize(checksum, file_modified_at, verified_at)
    self.checksum = checksum
    self.file_modified_at = file_modified_at
    self.verified_at = verified_at
  end
end

# 
# Computes checksums for all files in a directory tree and
# writes to a json file
#

def system_name?(path)
  File.basename(path)[0] == '.'
end

directory = ARGV.first
checksum_file = File.join(directory, CHECKSUM_FILE)
backup_file = checksum_file + '.backup'

# Load checksum file
begin
  previous_json = File.open(checksum_file, 'r') { |f| f.read }
  File.rename(checksum_file, backup_file)
  checksum_map = Oj.load(previous_json)
rescue => e
  checksum_map = {}
end

new_checksums = {}
changed_files = []

begin

  # Recursive directory walk to find all files we want to check.  This is how
  # we handle deleted files, handle renames, etc. When a found file
  # is in the old checksum map we copy it over

  puts "Finding all files in #{directory}"
  puts "\n"
  Find.find(directory) do |path|

    if File.directory?(path)
      Find.prune if system_name?(path) # skip directories starting with .
    elsif !system_name?(path)
      size = File.size(path)
      short_path = path[directory.length + 1..-1]

      if size > MAX_FILE_SIZE
        puts "Skipping large file (#{size.to_f / 1e6} MB): #{short_path}"
        next
      end

      new_checksums[short_path] = checksum_map[short_path]
    end
  end

  checksum_map = new_checksums # can toss out the checksum_map's memory
  files = checksum_map.keys


  #
  # Next step is to walk through all files in the new checksum list and validate them
  # We start at a random location so that it at leat makes progress if the app is 
  # stopped and restarted a lot
  #

  start = Random.new.rand(files.count)

  puts "Verifying #{files.count} files"
  [files[start..-1], files[0..start - 1]].each do |list|
    list.each do |short_path|

      full_path = File.join(directory,short_path)
      modified_at = File.mtime(full_path)
      checksum = Digest::SHA512.file(full_path).base64digest
      entry = checksum_map[short_path]

      if !entry.nil?
        if checksum == entry.checksum
          entry.verified_at = Time.now
          puts "Verified #{short_path}"
        elsif modified_at == entry.file_modified_at
          puts "[ERROR] checksum changed: #{short_path}"
          changed_files << { file_name: short_path, last_verified: entry.verified_at }
        else
          puts "[DEBUG] File changed: #{short_path}"
        end
      else
        puts "Added new file #{short_path}"
        checksum_map[short_path] = ChecksumEntry.new(checksum, modified_at, Time.now)
      end

    end
  end
rescue Interrupt
  puts "Exiting early!"
rescue => e
  puts e.message
end

#
# Write checksum file for next time
#
begin
  json = Oj.dump(checksum_map)
  File.open(checksum_file, 'w') { |f| f.write(json) }
  puts "\nSuccessfully wrote checksums to #{checksum_file}"
  File.delete(backup_file)
rescue => e
  puts e.message
end

if changed_files.any?
  puts "\nAll changed files"
  changed_files.each { |x| puts "#{x[:file_name]}, #{x[:last_verified]}" }
else
  puts "\nNo problems found!"
end