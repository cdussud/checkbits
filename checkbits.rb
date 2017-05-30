require 'digest'
require 'find'
require 'bundler'
Bundler.require

CHECKSUM_FILE = 'checkbits.json'
MAX_FILE_SIZE = 30_000_000 # 30MB

# Next up
# - save state even if the attached volume is disconnected
# - or periodically save the state? 
# - maybe progress indication
# - maybe start where we last left off instead of random

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
  file_to_load =
    if File.exist?(checksum_file)
      FileUtils.copy(checksum_file, backup_file)
      checksum_file
    else
      puts "Couldn't find main json file -- attempting to use backup"
      backup_file
    end

  previous_json = File.open(file_to_load, 'r') { |f| f.read }
  checksum_map = Oj.load(previous_json)
rescue => e
  puts "Error: #{e.message}. Starting with blank file"
  checksum_map = {}
end

new_checksums = {}
failed_files = []
changed_files = []

begin

  #
  # Recursive directory walk to find all files we want to check.  This is how
  # we handle deleted files, handle renames, etc. When a found file
  # is in the old checksum map we copy it over
  #

  puts "Finding all files in #{directory}"
  start_time = Time.now
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

  puts "\nFound all files in #{Time.now - start_time} seconds"
  puts "\n"

  checksum_map = new_checksums # can toss out the checksum_map's memory
  files = checksum_map.keys


  #
  # Next step is to walk through all files in the new checksum list and validate them
  # We start at a random location so that it at least makes progress if the app is 
  # stopped and restarted a lot
  #

  start = Random.new.rand(files.count)
  start_time = Time.now

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
        elsif modified_at.to_i == entry.file_modified_at.to_i
          puts "[ERROR] checksum changed: #{short_path}"
          failed_files << OpenStruct.new(file_name: short_path, last_verified: entry.verified_at)
        else
          puts "[DEBUG] File changed: #{short_path}"
          changed_files << OpenStruct.new(file_name: short_path, last_verified: entry.verified_at)
        end
      else
        puts "Added new file #{short_path}"
        checksum_map[short_path] = ChecksumEntry.new(checksum, modified_at, Time.now)
      end

    end
  end

  puts "Verification complete in #{Time.now - start_time} seconds"
rescue Interrupt
  puts "Exiting early -- saving progress!"
rescue => e
  puts e.message
end


#
# Write checksum file for next time
#

begin
  json = Oj.dump(checksum_map)
  File.open(checksum_file, 'w') { |f| f.write(json) }
  puts "\nSuccessfully wrote #{files.count} checksums to #{checksum_file}"
rescue => e
  puts e.message
end

if changed_files.any?
  puts "\n[DEBUG] Changed files"
  changed_files.each { |x| puts "#{x.file_name}" }
end

if failed_files.any?
  puts "\nFound some possibly corrupted files"
  failed_files.each { |x| puts "#{x.file_name}: #{x.last_verified}" }
else
  puts "\nNo problems found!"
end