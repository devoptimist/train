# encoding: utf-8
#
# author: Christoph Hartmann
# author: Dominik Richter

require 'train/file/local'
require 'train/file/remote'
require 'train/extras/stat'

module Train
  class File # rubocop:disable Metrics/ClassLength
    def initialize(backend, path, follow_symlink = true)
      @backend = backend
      @path = path || ''
      @follow_symlink = follow_symlink

      sanitize_filename(path)
    end

    # This method gets override by particular os class.
    def sanitize_filename(_path)
      nil
    end

    # interface methods: these fields should be implemented by every
    # backend File
    DATA_FIELDS = %w{
      exist? mode owner group uid gid content mtime size selinux_label path
    }.freeze

    DATA_FIELDS.each do |m|
      define_method m.to_sym do
        fail NotImplementedError, "File must implement the #{m}() method."
      end
    end

    def to_json
      res = Hash[DATA_FIELDS.map { |x| [x, method(x).call] }]
      # additional fields provided as input
      res['type'] = type
      res['follow_symlink'] = @follow_symlink
      res
    end

    def type
      :unknown
    end

    def source
      if @follow_symlink
        self.class.new(@backend, @path, false)
      else
        self
      end
    end

    def source_path
      @path
    end

    # product_version is primarily used by Windows operating systems only and will be overwritten
    # in Windows-related classes. Since this field is returned for all file objects, the acceptable
    # default value is nil
    def product_version
      nil
    end

    # file_version is primarily used by Windows operating systems only and will be overwritten
    # in Windows-related classes. Since this field is returned for all file objects, the acceptable
    # default value is nil
    def file_version
      nil
    end

    def version?(version)
      product_version == version or
        file_version == version
    end

    def block_device?
      type.to_s == 'block_device'
    end

    def character_device?
      type.to_s == 'character_device'
    end

    def pipe?
      type.to_s == 'pipe'
    end

    def file?
      type.to_s == 'file'
    end

    def socket?
      type.to_s == 'socket'
    end

    def directory?
      type.to_s == 'directory'
    end

    def symlink?
      source.type.to_s == 'symlink'
    end

    def owned_by?(sth)
      owner == sth
    end

    def path
      if symlink? && @follow_symlink
        link_path
      else
        @path
      end
    end

    # if the OS-specific file class supports inquirying as to whether the
    # file/device is mounted, the #mounted method should return a command
    # object whose stdout will not be nil if indeed the device is mounted.
    #
    # if the OS-specific file class does not support checking for mount
    # status, the method should not be implemented and this method will
    # return false.
    def mounted?
      return false unless respond_to?(:mounted)

      !mounted.nil? && !mounted.stdout.nil? && !mounted.stdout.empty?
    end

    def md5sum
      return perform_checksum(:md5) unless @backend.os.family == 'windows'

      perform_checksum_windows(:md5)
    end

    def sha256sum
      return perform_checksum(:sha256) unless @backend.os.family == 'windows'

      perform_checksum_windows(:sha256)
    end

    private

    def md5_command
      case @backend.os.family
      when 'darwin'
        # `-r` reverses output to match `md5sum`
        'md5 -r'
      when 'solaris'
        'digest -a md5'
      else
        'md5sum'
      end
    end

    def sha256_command
      case @backend.os.family
      when 'darwin', 'hpux', 'qnx'
        'shasum -a 256'
      when 'solaris'
        'digest -a sha256'
      else
        'sha256sum'
      end
    end

    def perform_checksum(method)
      case method
      when :md5
        cmd = "#{md5_command} #{@path}"
      when :sha256
        cmd = "#{sha256_command} #{@path}"
      end

      res = @backend.run_command(cmd)
      return res.stdout.split(' ').first if res.exit_status == 0

      raise_checksum_error(cmd, res)
    end

    def perform_checksum_windows(method)
      cmd = "CertUtil -hashfile #{@path} #{method.to_s.upcase}"

      res = @backend.run_command(cmd)
      return res.stdout.split("\r\n")[1].tr(' ', '') if res.exit_status == 0

      raise_checksum_error(cmd, res)
    end

    def raise_checksum_error(cmd, res)
      fail "Failed to get checksum with `#{cmd}`.\n" \
           "STDOUT: #{res.stdout}\n" \
           "STDERR: #{res.stderr}\n"
    end
  end
end
