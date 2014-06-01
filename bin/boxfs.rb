#! /usr/bin/ruby
#
# FuSE file system for OpenBox.
#
# http://rubyforge.org/projects/boxfs-ruby/
#
# Copyright (c) 2008-2010 Tomohiko Ariki.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

#  This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'fusefs'
require 'rubygems'
gem 'boxrubylib'
require 'boxrubylib'
require 'digest/sha1'

class BoxFS < FuseFS::FuseDir
  @@debug = false
  attr_reader :boxclient
  
  def BoxFS.debug=(v)
    @@debug = v
    if @@debug 
      puts "Debug mode is now ON"
    else
      puts "Debug mode is now OFF"
    end
  end
  
  def initialize(apiKey)
    @boxclient = BoxClientLib::BoxRestClient.new(apiKey)
    @dir = "/tmp/boxfs"
    Dir.mkdir(@dir) unless File.directory?(@dir)
    @openfiles = {}
    @written = []
    @newfiles = []
  end
  
  # Return an array of file and dirnames within <path>.
  def contents(path)
    debug("contents : path = #{path}")
    contents = Array.new
    folderInfo = walkPath(0, path)
    return contents if folderInfo.nil?
    if !folderInfo.childFolderList.nil?
      folderInfo.childFolderList.each do |childFolder|
        debug("contents : folder = #{childFolder.folderName}")
        contents.push(childFolder.folderName)
      end
    end
    if !folderInfo.fileList.nil?
      folderInfo.fileList.each do |file|
        debug("contents : file = #{file.fileName}")
        contents.push(file.fileName)
      end      
    end
    return contents
  rescue
    puts $!.message if @debug
    return nil
  end
  
  # Return true if <path> is a directory.
  # :directory? will be checked before :contents
  def directory?(path)
    debug("directory? : path = #{path}")
    itemInfo = walkPath(0, path)
    return false if itemInfo.nil?
    return false if itemInfo.kind_of?(BoxClientLib::FileInFolderInfo)
    debug("directory? : true")
    return true
  rescue
    puts $!.message if @debug
    return false
  end
  
  # Return true if <path> is a file (not a directory).
  # :file? will be checked before :read_file
  def file?(path)
    debug("file? : path = #{path}")
    itemInfo = walkPath(0, path)
    return false if itemInfo.nil?
    return false if itemInfo.kind_of?(BoxClientLib::FolderInfo)
    debug("file? : true")
    return true
  rescue
    puts $!.message if @debug
    return false
  end
  
  # Return true if <path> is an executable file.
  def executable?(path)
    debug("executable? : path = #{path}")
    return true
  end
  
  # Return the file size.
  def size(path)
    debug("size : path = #{path}")
    if directory?(path)
      return "4096"
    end
    
    fileInfo = walkPath(0, path)
    return fileInfo.size
  end
  
  # Return true if the user can write to file at <path>.
  # TODO : Examine about folder permission.
  def can_write?(path)
    debug("can_write? : path = #{path}")
    true
  end 
  
  # Return true if the user can delete file at <path>.
  # TODO : Examine about file permission.
  def can_delete?(path)
    debug("can_delete? : path = #{path}")
    return true
  end 
  
  # Delete the file at <path>.
  # :file? will be checked before :can_delete?
  # :can_delete? will be checked before :delete
  def delete(path)  
    debug("delete : path = #{path}")
    fileInfo = walkPath(0, path)
    @boxclient.delete("file", fileInfo.fileId)
    local = local_path(path)
    File.delete(local) if File.exists?(local)
    return true
  rescue
    puts $!.message if @debug
    return false
  end
  
  # Return true if user can make a directory at <path>.
  # TODO : Examine about folder permission.
  def can_mkdir?(path)
    debug("can_mkdir? : path = #{path}")
    return true
  end 
  
  # Make a directory at path.
  # :directory? is usually called on the directory
  # The FS wants to make a new directory in, before
  # this can occur.
  # :directory? will be checked.
  # :can_mkdir? is called only if :directory? is false.
  # :can_mkdir? will be checked before :mkdir
  def mkdir(path)
    debug("mkdir : path = #{path}")
    dir, base = File.split(path)
    parentInfo = walkPath(0, dir)
    @boxclient.createFolder(parentInfo.folderId, base, 0)
    return true
  rescue
    puts $!.message if @debug
    return false
  end 
  
  # Return true if user can remove directory at <path>.
  # TODO : Examine about folder permission.
  def can_rmdir?(path) 
    debug("can_rmdir? : path = #{path}")
    return true
  end
  
  # Remove it.
  # :directory? will be checked before :can_rmdir?
  # :can_rmdir? will be checked before :rmdir
  def rmdir(path)    
    debug("rmdir : path = #{path}")
    folderInfo = walkPath(0, path)
    @boxclient.delete("folder", folderInfo.folderId)    
    return true
  rescue
    puts $!.message if @debug
    return false
  end
  
  def touch(path)       
    debug("touch : path = #{path}")    
  end 
  
  def raw_open(path, mode)
    debug("raw_open : path = #{path}, mode = #{mode}")
    return true if @openfiles.has_key?(path) and not @openfiles[path].closed?
 
    fileInfo = walkPath(0, path)
    local = local_path(path)
    
    if fileInfo
      # File exists on Box.net, download to local disk.
      File.open(local, "w") do |file|
        debug("raw_open : download file id = #{fileInfo.fileId}")
        data = @boxclient.fileDownload(fileInfo.fileId)
        file.write(data)
        file.close
      end
    else
      return false if mode == "r"
      @newfiles << path
    end

    @openfiles[path] = File.open(local, convertMode(mode))
    return true
  rescue
    puts $!.message if @debug
    return false
  end
    
  def raw_close(path)
    debug("raw_close : path = #{path}")
    file = @openfiles[path]
    return false unless file    
    file.close
    @openfiles.delete path

    local = local_path(path)
    dir, remote = File.split(path)
    debug("raw_close : dir = #{dir}, remote = #{remote}")

    if @newfiles.include?(path)
      parentInfo = walkPath(0, dir)
      @newfiles.delete(path)
      uploadLocalFile(local, remote, parentInfo.folderId)
      if @written.include? path
        @written.delete path
      end
      return true
    end
    
    if @written.include? path
      fileInfo = walkPath(0, path)
      @written.delete path
      overWriteLocalFile(local, remote, fileInfo.fileId)
      return true
    end
    
    return true
  rescue
    puts $!.message if @debug
    return false
  end
  
  def raw_read(path, off, size)
    debug("raw_read : path = #{path}, offset = #{off}, size = #{size}")
    file = @openfiles[path]
    return nil unless file
    
    file.seek(off, File::SEEK_SET)
    file.read(size)
  rescue
    puts $!.message if @debug
    return 0
  end
  
  def raw_write(path, off, size, buf)
    debug("raw_write : path = #{path}, off = #{off}, size = #{size}")
    file = @openfiles[path]
    return nil unless file
    
    @written << path

    file.seek(off, File::SEEK_SET)
    file.write(buf[0, size])    
  rescue
    puts $!.message if @debug
    return 0
  end
  
  private

  def overWriteLocalFile(local, remote, fileId)
    debug("overWriteLocalFile : local = #{local}, remote = #{remote}, fileId = #{fileId}")
    f = File.open(local, "r")
    data = f.read
    f.close
    return @boxclient.fileOverWrite(remote, data, fileId, 0, nil, nil)
  end

  def uploadLocalFile(local, remote, folderId)
    debug("uploadLocalFile : local = #{local}, remote = #{remote}, folderId = #{folderId}")
    f = File.open(local, "r")
    data = f.read
    f.close
    return @boxclient.fileUpload(remote, data, folderId, 0, nil, nil)
  end

  def local_path(path)
    debug("local_path : path = #{path}")
    append = Digest::SHA1.hexdigest(path)
    debug("local_path : append = #{append}")
    name = File.basename(path)
    debug("local_path : name = #{name}")
    File.join(@dir, "#{name}-#{append}")
  end

  def lookupFolderInfo(folderInfo, name)
    debug("lookupFolderInfo : lookup name = #{name}")
    return nil if folderInfo.childFolderList.nil?
    folderInfo.childFolderList.each do |childFolder|
      debug("lookupFolderInfo : folder name = #{childFolder.folderName}")
      return childFolder if childFolder.folderName == name
    end
    return nil
  end
  
  def lookupFileInfo(folderInfo, name)
    debug("lookupFileInfo : lookup name = #{name}")
    return nil if folderInfo.fileList.nil? 
    folderInfo.fileList.each do |file|
      debug("lookupFileInfo : file name = #{file.fileName}")
      return file if file.fileName == name
    end
    return nil
  end
  
  def walkPath(targetId, path)
    debug("walkPath : targetId = #{targetId}, path = #{path}")
    base, rest = split_path(path)
    debug("walkPath : base = #{base}, rest = #{rest}")
    targetInfo = @boxclient.getFolderInfo(targetId, nil)

    if base.nil?
      return targetInfo 
    elsif rest.nil?
      folderInfo = lookupFolderInfo(targetInfo, base)
      return folderInfo unless folderInfo.nil?
      fileInfo = lookupFileInfo(targetInfo, base)
      return fileInfo unless fileInfo.nil?
      return nil
    end
    folderInfo = lookupFolderInfo(targetInfo, base)
    return nil if folderInfo.nil?
    walkPath(folderInfo.folderId, rest) 
  end
  
  def convertMode(mode)
    if mode == "wa"
      return "a"
    elsif mode == "rw"
      return "r+"
    elsif mode == "rwa"    
      return "a+"
    else
     return mode 
    end
  end
  
  def debug(msg)
    puts "[DEBUG] #{msg}" if @@debug
  end
end

def usage
  puts "Usage: #{__FILE__} <directory> <username> <password>"
  exit
end

if __FILE__ == $0
  usage if ARGV.length < 3
  
  begin
    dir, username, password = ARGV.shift, ARGV.shift, ARGV.shift
    
    unless File.directory? dir
      puts "Usage: #{dir} is not a directory."
      usage
    end
    
    BoxFS.debug = true
    
    fs = BoxFS.new("iji48atyxxjj3a3ds92uudplvf734uma")
    
    # Login
    ticket = fs.boxclient.getTicket()

    while true
      begin
        puts "Login at http://www.box.net/api/1.0/auth/#{ticket}."
        puts "If you finish login process, press any key."
        gets
        authToken = fs.boxclient.getAuthToken(ticket)
        break
      rescue
        puts "Your login isn't success now. Try again? [Y/N]"
        c = gets.chomp
        break if (c != 'y') && (c != 'Y')
      end
    end

    puts "You are successfully login."
    
    exit if authToken.nil?
    FuseFS.set_root(fs)
    FuseFS.mount_under dir
    FuseFS.run
    
  rescue => e
    if e.kind_of?(BoxClientLib::BoxServiceError)
      puts e.to_s
    else
      puts "Caught unhandled error : " + e.message
    end
    puts e.backtrace
  end
end