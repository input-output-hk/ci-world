#!/usr/bin/env ruby

require 'set'
require 'open3'
require 'fileutils'

# 1: dump old database
# 2: remove paths from previous container closure
# 3: merge paths from new container closure

DIR = '/etc/nix-db-merge/'
current_system_registration = File.join(DIR, 'registration')
current_store_paths = File.join(DIR, 'store-paths')
previous_system_registration = File.join(DIR, 'previous-registration')
previous_store_paths = File.join(DIR, 'previous-store-paths')
loadable_registrations_temp = File.join(DIR, 'loadable.tmp')

def read_registration_entry(rd)
  path = rd.readline
  nar_hash = rd.readline
  nar_size = rd.readline.to_i
  rd.readline
  references_count = rd.readline.to_i
  references = Array.new(references_count){ rd.readline }
  return path, nar_hash, nar_size, references
end

def write_registration_entry(wr, path, nar_hash, nar_size, references)
  p path
  wr << path
  wr << nar_hash
  wr << "#{nar_size}\n"
  wr << "\n"
  wr << "#{references.size}\n"
  wr << references.join
end

if File.file?(previous_store_paths)
  exit if FileUtils.identical?(previous_store_paths, current_store_paths)

  curr = Set.new(File.readlines(current_store_paths))
  prev = Set.new(File.readlines(previous_store_paths))
  seen = Set.new

  # This may fail on the first system boot
  File.open(loadable_registrations_temp, 'w+') do |loadable|
    Open3.popen3('nix-store', '--dump-db') do |si, so, se|
      until so.eof?
        path, nar_hash, nar_size, references = read_registration_entry(so)

        next if curr.include?(path) && !prev.include?(path)

        seen << path

        write_registration_entry(loadable, path, nar_hash, nar_size, references)
      end
    end

    File.open(current_system_registration) do |fd|
      until fd.eof?
        path, nar_hash, nar_size, references = read_registration_entry(fd)

        next if seen.include?(path)

        write_registration_entry(loadable, path, nar_hash, nar_size, references)
      end
    end
  end
else
  FileUtils.cp(current_system_registration, loadable_registrations_temp)
end

FileUtils.cp(current_system_registration, previous_system_registration)
FileUtils.cp(current_store_paths, previous_store_paths)

Open3.popen2e('nix-store', '--load-db') do |sin, soe|
  File.open(loadable_registrations_temp) do |fd|
    IO.copy_stream(fd, sin)
  end
end

# FileUtils.rm_f(loadable_registrations_temp)
