##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Post
  include Msf::Post::Windows::Accounts

  def initialize(info={})
    super(update_info(info,
      'Name'           => "Windows Gather Directory Permissions Enumeration",
      'Description'    => %q{
        This module enumerates directories and lists the permissions set
        on found directories. Please note: if the PATH option isn't specified,
        then the module will start enumerate whatever is in the target machine's
        %PATH% variable.
      },
      'License'        => MSF_LICENSE,
      'Platform'       => ['win'],
      'SessionTypes'   => ['meterpreter'],
      'Author'         =>
        [
          'Kx499',
          'Ben Campbell',
          'sinn3r'
        ]
    ))

    register_options(
      [
        OptString.new('PATH', [ false, 'Directory to begin search from', '']),
        OptEnum.new('FILTER', [ false, 'Filter to limit results by', 'NA', [ 'NA', 'R', 'W', 'RW' ]]),
        OptInt.new('DEPTH', [ true, 'Depth to drill down into subdirs, O = no limit',0]),
      ])
  end

  def enum_subdirs(perm_filter, dpath, maxdepth, token)
    filter = datastore['FILTER']
    filter = nil if datastore['FILTER'] == 'NA'

    begin
      dirs = session.fs.dir.foreach(dpath)
    rescue Rex::Post::Meterpreter::RequestError
      # Sometimes we cannot see the dir
      dirs = []
    end

    if maxdepth >= 1 or maxdepth < 0
      dirs.each do|d|
        next if d =~ /^(\.|\.\.)$/
        realpath = dpath + '\\' + d
        if session.fs.file.stat(realpath).directory?
          perm = check_dir_perms(realpath, token)
          if perm_filter and perm and perm.include?(perm_filter)
            print_status(perm + "\t" + realpath)
          end
          enum_subdirs(perm_filter, realpath, maxdepth - 1,token)
        end
      end
    end
  end

  def get_paths
    p = datastore['PATH']
    return [p] if not p.nil? and not p.empty?

    begin
      p = cmd_exec("cmd.exe", "/c echo %PATH%")
    rescue Rex::Post::Meterpreter::RequestError => e
      vprint_error(e.message)
      return []
    end
    print_status("Option 'PATH' isn't specified. Using system %PATH%")
    if p.include?(';')
      return p.split(';')
    else
      return [p]
    end
  end

  def get_token
    print_status("Getting impersonation token...")
    begin
      t = get_imperstoken()
    rescue ::Exception => e
      # Failure due to timeout, access denied, etc.
      t = nil
      vprint_error("Error #{e.message} while using get_imperstoken()")
      vprint_error(e.backtrace)
    end
    return t
  end

  def enum_perms(perm_filter, token, depth, paths)
    paths.each do |path|
      next if path.empty?
      path = path.strip

      print_status("Checking directory permissions from: #{path}")

      perm = check_dir_perms(path, token)
      if not perm.nil?
        # Show the permission of the parent directory
        if perm_filter and perm.include?(perm_filter)
          print_status(perm + "\t" + path)
        end

        #call recursive function to loop through and check all sub directories
        enum_subdirs(perm_filter, path, depth, token)
      end
    end
  end

  def run
    perm_filter = datastore['FILTER']
    perm_filter = nil if datastore['FILTER'] == 'NA'

    paths = get_paths
    if paths.empty?
      print_error("Unable to get the path")
      return
    end

    depth = -1
    if datastore['DEPTH'] > 0
      depth = datastore['DEPTH']
    end

    t = get_token

    unless t
      print_error("Getting impersonation token failed")
    else
      print_status("Got token: #{t.to_s}...")
      enum_perms(perm_filter, t, depth, paths)
    end
  end
end
