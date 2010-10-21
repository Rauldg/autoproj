require 'tempfile'
module Autoproj
    class OSDependencies
        def self.load(file)
            file = File.expand_path(file)
            begin
                data = YAML.load(File.read(file)) || Hash.new
                verify_definitions(data)
            rescue ArgumentError => e
                raise ConfigError, "error in #{file}: #{e.message}"
            end

            OSDependencies.new(data, file)
        end

        class << self
            attr_reader :aliases
            attr_accessor :force_osdeps
            attr_accessor :gem_with_prerelease
        end
        @aliases = Hash.new

        attr_writer :silent
        def silent?; @silent end

        def self.alias(old_name, new_name)
            @aliases[new_name] = old_name
        end

        def self.autodetect_ruby
            ruby_package =
                if RUBY_VERSION < "1.9.0" then "ruby18"
                else "ruby19"
                end
            self.alias(ruby_package, "ruby")
        end

        AUTOPROJ_OSDEPS = File.join(File.expand_path(File.dirname(__FILE__)), 'default.osdeps')
        def self.load_default
            file = ENV['AUTOPROJ_DEFAULT_OSDEPS'] || AUTOPROJ_OSDEPS
            if !File.file?(file)
                Autoproj.progress "WARN: #{file} (from AUTOPROJ_DEFAULT_OSDEPS) is not a file, falling back to #{AUTOPROJ_OSDEPS}"
                file = AUTOPROJ_OSDEPS
            end
            OSDependencies.load(file)
        end

        # The information contained in the OSdeps files, as a hash
        attr_reader :definitions
        # The information as to from which osdeps file the current package
        # information in +definitions+ originates. It is a mapping from the
        # package name to the osdeps file' full path
        attr_reader :sources

        # The Gem::SpecFetcher object that should be used to query RubyGems, and
        # install RubyGems packages
        def gem_fetcher
            if !@gem_fetcher
                Autobuild.progress "looking for RubyGems updates"
                @gem_fetcher = Gem::SpecFetcher.fetcher
            end
            @gem_fetcher
        end

        def initialize(defs = Hash.new, file = nil)
            @definitions = defs.to_hash
            @sources     = Hash.new
            @installed_packages = Array.new
            if file
                defs.each_key do |package_name|
                    sources[package_name] = file
                end
            end
            @silent = true
            @filter_uptodate_packages = true
        end

        # Returns the full path to the osdeps file from which the package
        # definition for +package_name+ has been taken
        def source_of(package_name)
            sources[package_name]
        end

        # Merges the osdeps information of +info+ into +self+. If packages are
        # defined in both OSDependencies objects, the information in +info+
        # takes precedence
        def merge(info)
            root_dir = nil
            @definitions = definitions.merge(info.definitions) do |h, v1, v2|
                if v1 != v2
                    root_dir ||= "#{Autoproj.root_dir}/"
                    old = source_of(h).gsub(root_dir, '')
                    new = info.source_of(h).gsub(root_dir, '')
                    Autoproj.warn("osdeps definition for #{h}, previously defined in #{old} overriden by #{new}")
                end
                v2
            end
            @sources = sources.merge(info.sources)
        end

        # Perform some sanity checks on the given osdeps definitions
        def self.verify_definitions(hash)
            hash.each do |key, value|
                if !key.kind_of?(String)
                    raise ArgumentError, "invalid osdeps definition: found an #{key.class}. Don't forget to put quotes around numbers"
                end
                next if !value
                if value.kind_of?(Array) || value.kind_of?(Hash)
                    verify_definitions(value)
                else
                    if !value.kind_of?(String)
                        raise ArgumentError, "invalid osdeps definition: found an #{value.class}. Don't forget to put quotes around numbers"
                    end
                end
            end
        end

        # Returns true if it is possible to install packages for the operating
        # system on which we are installed
        def self.supported_operating_system?
            if @supported_operating_system.nil?
                osdef = operating_system
                @supported_operating_system =
                    if !osdef then false
                    else
                        OS_AUTO_PACKAGE_INSTALL.has_key?(osdef[0])
                    end
            end
            return @supported_operating_system
        end

        # Autodetects the operating system name and version
        #
        # +osname+ is the operating system name, all in lowercase (e.g. ubuntu,
        # arch, gentoo, debian)
        #
        # +versions+ is a set of names that describe the OS version. It includes
        # both the version number (as a string) and/or the codename if there is
        # one.
        #
        # Examples: ['debian', ['sid', 'unstable']] or ['ubuntu', ['lucid lynx', '10.04']]
        def self.operating_system
            if @operating_system
                return @operating_system
            elsif Autoproj.has_config_key?('operating_system')
                return (@operating_system = Autoproj.user_config('operating_system'))
            end

            Autoproj.progress "  autodetecting the operating system"
            if data = os_from_lsb
                if data[0] != "debian"
                    # if on Debian proper, fall back to reading debian_version,
                    # as sid is listed as lenny by lsb-release
                    @operating_system = data
                end
            end

            if !@operating_system
                # Need to do some heuristics unfortunately
                @operating_system =
                    if File.exists?('/etc/debian_version')
                        codename = [File.read('/etc/debian_version').strip]
                        if codename.first =~ /sid/
                            codename << "unstable" << "sid"
                        end
                        ['debian', codename]
                    elsif File.exists?('/etc/gentoo-release')
                        release_string = File.read('/etc/gentoo-release').strip
                        release_string =~ /^.*([^\s]+)$/
                            version = $1
                        ['gentoo', [version]]
                    elsif File.exists?('/etc/arch-release')
                        ['arch', []]
                    end
            end

            if !@operating_system
                return
            end

            # Normalize the names to lowercase
            @operating_system =
                [@operating_system[0].downcase,
                 @operating_system[1].map(&:downcase)]
            Autoproj.change_option('operating_system', @operating_system, true)
            @operating_system
        end

        def self.os_from_lsb
            has_lsb_release = `which lsb_release`
            return unless $?.success?

            distributor = `lsb_release -i -s`
            distributor = distributor.strip.downcase
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            return [distributor, [codename, version]]
        end

        # On a dpkg-enabled system, checks if the provided package is installed
        # and returns true if it is the case
        def self.dpkg_package_installed?(package_name)
            if !@dpkg_installed_packages
                @dpkg_installed_packages = Set.new
                dpkg_status = File.readlines('/var/lib/dpkg/status')
                dpkg_status.grep(/^(Package|Status)/).
                    each_slice(2) do |package, status|
                        if status.chomp == "Status: install ok installed"
                            @dpkg_installed_packages << package.split[1].chomp
                        end
                    end
            end
            
            if package_name =~ /^(\w[a-z0-9+-.]+)/
                @dpkg_installed_packages.include?($1)
            else
                Autoproj.progress "WARN: #{package_name} is not a valid Debian package name"
                false
            end
        end

        GAIN_ROOT_ACCESS = <<-EOSCRIPT
# Gain root access using sudo
if test `id -u` != "0"; then
    exec sudo /bin/bash $0 "$@"

fi
        EOSCRIPT

        OS_PACKAGE_CHECK = {
            'debian' => method(:dpkg_package_installed?),
            'ubuntu' => method(:dpkg_package_installed?)
        }
        OS_USER_PACKAGE_INSTALL = {
            'debian' => "apt-get install '%s'",
            'ubuntu' => "apt-get install '%s'",
            'gentoo' => "emerge '%s'",
            'arch' => "pacman '%s'"
        }

        OS_AUTO_PACKAGE_INSTALL = {
            'debian' => "export DEBIAN_FRONTEND=noninteractive; apt-get install -y '%s'",
            'ubuntu' => "export DEBIAN_FRONTEND=noninteractive; apt-get install -y '%s'",
            'gentoo' => "emerge --noreplace '%s'",
            'arch' => "pacman -Sy --noconfirm '%s'"
        }

        NO_PACKAGE       = 0
        WRONG_OS         = 1
        WRONG_OS_VERSION = 2
        IGNORE           = 3
        PACKAGES         = 4
        UNKNOWN_OS       = 7
        AVAILABLE        = 10

        # Check for the definition of +name+ for this operating system
        #
        # It can return
        #
        # NO_PACKAGE::
        #   there are no package definition for +name
        # UNKNOWN_OS::
        #   this is not an OS autoproj knows how to deal with
        # WRONG_OS::
        #   there are a package definition, but not for this OS
        # WRONG_OS_VERSION::
        #   there is a package definition for this OS, but not for this
        #   particular version of the OS
        # IGNORE::
        #   there is a package definition that told us to ignore the package
        # [PACKAGES, definition]::
        #   +definition+ is an array of package names that this OS's package
        #   manager can understand
        def resolve_package(name)
            os_name, os_version = OSDependencies.operating_system

            dep_def = definitions[name]
            if !dep_def
                return NO_PACKAGE
            end

            if !os_name
                return UNKNOWN_OS
            end

            # Find a matching entry for the OS name
            os_entry = dep_def.find do |name_list, data|
                name_list.split(',').
                    map(&:downcase).
                    any? { |n| n == os_name }
            end

            if !os_entry
                return WRONG_OS
            end

            data = os_entry.last

            # This package does not need to be installed on this operating system (example: build tools on Gentoo)
            if !data || data == "ignore"
                return IGNORE
            end

            if data.kind_of?(Hash)
                version_entry = data.find do |version_list, data|
                    version_list.to_s.split(',').
                        map(&:downcase).
                        any? do |v|
                            os_version.any? { |osv| Regexp.new(v) =~ osv }
                        end
                end

                if !version_entry
                    return WRONG_OS_VERSION
                end
                data = version_entry.last
            end

            if data.respond_to?(:to_ary)
                return [PACKAGES, data]
            elsif data.to_str =~ /\w+/
                return [PACKAGES, [data.to_str]]
            else
                raise ConfigError, "invalid package specificiation #{data} in #{source_of(name)}"
            end
        end

        # Resolves the given OS dependencies into the actual packages that need
        # to be installed on this particular OS.
        #
        # Raises ConfigError if some packages can't be found
        def resolve_os_dependencies(dependencies)
            os_name, os_version = OSDependencies.operating_system

            os_packages    = []
            dependencies.each do |name|
                result = resolve_package(name)
                if result == NO_PACKAGE
                    raise ConfigError, "there is no osdeps definition for #{name}"
                elsif result == WRONG_OS
                    raise ConfigError, "there is an osdeps definition for #{name}, but not for this operating system"
                elsif result == WRONG_OS_VERSION
                    raise ConfigError, "there is an osdeps definition for #{name}, but not for this particular operating system version"
                elsif result == IGNORE
                    next
                elsif result[0] == PACKAGES
                    os_packages.concat(result[1])
                end
            end

            if !OS_AUTO_PACKAGE_INSTALL.has_key?(os_name)
                raise ConfigError, "I don't know how to install packages on #{os_name}"
            end

            return os_packages
        end


        def generate_user_os_script(os_name, os_packages)
            if OS_USER_PACKAGE_INSTALL[os_name]
                (OS_USER_PACKAGE_INSTALL[os_name] % [os_packages.join("' '")])
            else generate_auto_os_script(os_name, os_packages)
            end
        end
        def generate_auto_os_script(os_name, os_packages)
            (OS_AUTO_PACKAGE_INSTALL[os_name] % [os_packages.join("' '")])
        end

        # Returns true if +name+ is an acceptable OS package for this OS and
        # version
        def has?(name)
            availability_of(name) == AVAILABLE
        end

        # If +name+ is an osdeps that is available for this operating system,
        # returns AVAILABLE. Otherwise, returns the same error code than
        # resolve_package.
        def availability_of(name)
            osdeps, gemdeps = partition_packages([name].to_set)
            if !osdeps.empty?
                status = resolve_package(name)
                if status.respond_to?(:to_ary) || status == IGNORE
                    AVAILABLE
                else
                    status
                end
            else
                AVAILABLE
            end
        end

        # call-seq:
        #   partition_packages(package_names) => os_packages, gem_packages
        #
        # Resolves the package names listed in +package_set+, and returns a set
        # of packages that have to be installed using the platform's native
        # package manager, and the set of packages that have to be installed
        # using Ruby's package manager, RubyGems.
        #
        # Raises ConfigError if no package can be found
        def partition_packages(package_set, package_osdeps = Hash.new)
            package_set = package_set.
                map { |name| OSDependencies.aliases[name] || name }.
                to_set

            osdeps, gems = [], []
            package_set.to_set.each do |name|
                pkg_def = definitions[name]
                if !pkg_def
                    # Error cases are taken care of later, because that is were
                    # the automatic/manual osdeps logic lies
                    osdeps << name
                    next
                end

                pkg_def = pkg_def.dup

                if pkg_def.respond_to?(:to_str)
                    case(pkg_def.to_str)
                    when "ignore" then
                    when "gem" then
                        gems << name
                    else
                        # This is *not* handled later, as is the absence of a
                        # package definition. The reason is that it is a bad
                        # configuration file, and should be fixed by the user
                        raise ConfigError, "unknown OS-independent package management type #{pkg_def} for #{name}"
                    end
                else
                    pkg_def.delete_if do |distrib_name, defs|
                        if distrib_name == "gem"
                            gems.concat([*defs])
                            true
                        end
                    end
                    if !pkg_def.empty?
                        osdeps << name
                    end
                end
            end
            return osdeps, gems
        end

        def guess_gem_program
            if Autobuild.programs['gem']
                return Autobuild.programs['gem']
            end

            ruby_bin = Config::CONFIG['RUBY_INSTALL_NAME']
            if ruby_bin =~ /^ruby(.+)$/
                Autobuild.programs['gem'] = "gem#{$1}"
            else
                Autobuild.programs['gem'] = "gem"
            end
        end

        # Returns true if the osdeps system knows how to remove uptodate
        # packages from the needs-to-be-installed package list on this OS
        def can_filter_uptodate_packages?
            os_name, _ = OSDependencies.operating_system
            !!OS_PACKAGE_CHECK[os_name]
        end

        # Returns the set of packages in +packages+ that are not already
        # installed on this OS, if it is supported
        def filter_uptodate_os_packages(packages, os_name)
            check_method = OS_PACKAGE_CHECK[os_name]
            return packages.dup if !check_method

            packages.find_all { |pkg| !check_method[pkg] }
        end

        # Returns the set of RubyGem packages in +packages+ that are not already
        # installed, or that can be upgraded
        def filter_uptodate_gems(gems)
            # Don't install gems that are already there ...
            gems = gems.dup
            gems.delete_if do |name|
                version_requirements = Gem::Requirement.default
                installed = Gem.source_index.find_name(name, version_requirements)
                if !installed.empty? && Autobuild.do_update
                    # Look if we can update the package ...
                    dep = Gem::Dependency.new(name, version_requirements)
                    available = gem_fetcher.find_matching(dep, false, true, OSDependencies.gem_with_prerelease)
                    installed_version = installed.map(&:version).max
                    available_version = available.map { |(name, v), source| v }.max
                    if !available_version
                        raise ConfigError, "cannot find any gem with the name '#{name}'"
                    end
                    needs_update = (available_version > installed_version)
                    !needs_update
                else
                    !installed.empty?
                end
            end
            gems
        end

        HANDLE_ALL  = 'all'
        HANDLE_RUBY = 'ruby'
        HANDLE_OS   = 'os'
        HANDLE_NONE = 'none'

        def self.osdeps_mode_option_unsupported_os
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj is
usually able to install those automatically, but unfortunately your operating
system is not (yet) supported by autoproj's osdeps mechanism, it can only offer
you some limited support.

RubyGem packages are a cross-platform mechanism, and are therefore supported.
However, you will have to install the kind of OS dependencies (so-called OS
packages)

This option is meant to allow you to control autoproj's behaviour while handling
OS dependencies.

* if you say "ruby", the RubyGem packages will be installed.
* if you say "none", autoproj will not do anything related to the OS
  dependencies.

As any configuration value, the mode can be changed anytime by calling
an autoproj operation with the --reconfigure option (e.g. autoproj update
--reconfigure).

Finally, OS dependencies can be installed by calling "autoproj osdeps"
with the corresponding option (--all, --ruby, --os or --none). Calling
"autoproj osdeps" without arguments will also give you information as
to what you should install to compile the software successfully.
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (ruby, none) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'ruby',
		:doc => [short_doc, long_doc],
                :possible_values => %w{ruby none},
                :lowercase => true
        end

        def self.osdeps_mode_option_supported_os
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj
is able to install those automatically for you.

Advanced users may want to control this behaviour. Additionally, the
installation of some packages require administration rights, which you may
not have. This option is meant to allow you to control autoproj's behaviour
while handling OS dependencies.

* if you say "all", it will install all packages automatically.
  This requires root access thru 'sudo'
* if you say "ruby", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "os", only the OS-provided packages will be installed.
  Installing these packages requires root access.
* if you say "none", autoproj will not do anything related to the
  OS dependencies.

As any configuration value, the mode can be changed anytime by calling
an autoproj operation with the --reconfigure option (e.g. autoproj update
--reconfigure).

Finally, OS dependencies can be installed by calling "autoproj osdeps"
with the corresponding option (--all, --ruby, --os or --none).
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, ruby, os, none) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'all',
		:doc => message,
                :possible_values => %w{all ruby os none},
                :lowercase => true
        end

        def self.define_osdeps_mode_option
            if supported_operating_system?
                osdeps_mode_option_supported_os
            else
                osdeps_mode_option_unsupported_os
            end
        end

        def self.osdeps_mode_string_to_value(string)
            string = string.downcase
            case string
            when 'all'  then HANDLE_ALL
            when 'ruby' then HANDLE_RUBY
            when 'os'   then HANDLE_OS
            when 'none' then HANDLE_NONE
            else raise ArgumentError, "invalid osdeps mode string '#{string}'"
            end
        end

        # If set to true (the default), #install will try to remove the list of
        # already uptodate packages from the installed packages. Set to false to
        # install all packages regardless of their status
        attr_accessor :filter_uptodate_packages

        # Override the osdeps mode
        def osdeps_mode=(value)
            @osdeps_mode = OSDependencies.osdeps_mode_string_to_value(value)
        end

        # Returns the osdeps mode chosen by the user
        def osdeps_mode
            # This has two uses. It caches the value extracted from the
            # AUTOPROJ_OSDEPS_MODE and/or configuration file. Moreover, it
            # allows to override the osdeps mode by using
            # OSDependencies#osdeps_mode=
            if @osdeps_mode
                return @osdeps_mode
            end

            @osdeps_mode = OSDependencies.osdeps_mode
        end

        def self.osdeps_mode
            while true
                mode =
                    if !Autoproj.has_config_key?('osdeps_mode') &&
                        mode_name = ENV['AUTOPROJ_OSDEPS_MODE']
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode given through AUTOPROJ_OSDEPS_MODE (#{mode})"
                            nil
                        end
                    else
                        mode_name = Autoproj.user_config('osdeps_mode')
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode stored in configuration file"
                            nil
                        end
                    end

                if mode
                    @osdeps_mode = mode
                    return mode
                end

                # Invalid configuration values. Retry
                Autoproj.reset_option('osdeps_mode')
                ENV['AUTOPROJ_OSDEPS_MODE'] = nil
            end
        end

        # The set of packages that have already been installed
        attr_reader :installed_packages

        def osdeps_interaction_unknown_os(osdeps)
            puts <<-EOMSG
  #{Autoproj.color("The build process requires some other software packages to be installed on our operating system", :bold)}
  #{Autoproj.color("If they are already installed, simply ignore this message", :red)}"
  
    #{osdeps.join("\n    ")}

            EOMSG
            print Autoproj.color("Press ENTER to continue", :bold)
            STDOUT.flush
            STDIN.readline
            puts
            nil
        end

        def osdeps_interaction(osdeps, os_packages, shell_script, silent)
            if !OSDependencies.supported_operating_system?
                if silent
                    return false
                else
                    return osdeps_interaction_unknown_os(osdeps)
                end
            elsif OSDependencies.force_osdeps
                return true
            elsif osdeps_mode == HANDLE_ALL || osdeps_mode == HANDLE_OS
                return true
            elsif silent
                return false
            end

            # We're asked to not install the OS packages but to display them
            # anyway, do so now
            puts <<-EOMSG

  #{Autoproj.color("The build process and/or the packages require some other software to be installed", :bold)}
  #{Autoproj.color("and you required autoproj to not install them itself", :bold)}
  #{Autoproj.color("\nIf these packages are already installed, simply ignore this message\n", :red) if !can_filter_uptodate_packages?}
    The following packages are available as OS dependencies, i.e. as prebuilt
    packages provided by your distribution / operating system. You will have to
    install them manually if they are not already installed
    
      #{os_packages.sort.join("\n      ")}
    
    the following command line(s) can be run as root to install them:
    
      #{shell_script.split("\n").join("\n|   ")}

            EOMSG
            print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"
            STDOUT.flush
            STDIN.readline
            puts
            false
        end

        def gems_interaction(gems, cmdline, silent)
            if OSDependencies.force_osdeps
                return true
            elsif osdeps_mode == HANDLE_ALL || osdeps_mode == HANDLE_RUBY
                return true
            elsif silent
                return false
            end

            # We're not supposed to install rubygem packages but silent is not
            # set, so display information about them anyway
            puts <<-EOMSG
  #{Autoproj.color("The build process and/or the packages require some Ruby Gems to be installed", :bold)}
  #{Autoproj.color("and you required autoproj to not do it itself", :bold)}
    You can use the --all or --ruby options to autoproj osdeps to install these
    packages anyway, and/or change to the osdeps handling mode by running an
    autoproj operation with the --reconfigure option as for instance
    autoproj build --reconfigure
    
    The following command line can be used to install them manually
    
      #{cmdline.join(" ")}
    
    Autoproj expects these Gems to be installed in #{Autoproj.gem_home} This can
    be overriden by setting the AUTOPROJ_GEM_HOME environment variable manually

            EOMSG
            print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"

            STDOUT.flush
            STDIN.readline
            puts
            false
        end

        # Requests the installation of the given set of packages
        def install(packages, package_osdeps = Hash.new)
            handled_os = OSDependencies.supported_operating_system?
            # Remove the set of packages that have already been installed 
            packages -= installed_packages
            return if packages.empty?

            osdeps, gems = partition_packages(packages, package_osdeps)
            if handled_os
                os_name, os_version = OSDependencies.operating_system
                os_packages = resolve_os_dependencies(osdeps)
                if filter_uptodate_packages
                    os_packages = filter_uptodate_os_packages(os_packages, os_name)
                end
            end
            if filter_uptodate_packages
                gems   = filter_uptodate_gems(gems)
            end

            did_something = false

            if !osdeps.empty? && (!os_packages || !os_packages.empty?)
                if handled_os
                    shell_script = generate_auto_os_script(os_name, os_packages)
                    user_shell_script = generate_user_os_script(os_name, os_packages)
                end
                if osdeps_interaction(osdeps, os_packages, user_shell_script, silent?)
                    Autoproj.progress "  installing OS packages: #{os_packages.sort.join(", ")}"

                    if Autoproj.verbose
                        Autoproj.progress "Generating installation script for non-ruby OS dependencies"
                        Autoproj.progress shell_script
                    end

                    Tempfile.open('osdeps_sh') do |io|
                        io.puts "#! /bin/bash"
                        io.puts GAIN_ROOT_ACCESS
                        io.write shell_script
                        io.flush
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', '/bin/bash', io.path
                    end
                    did_something = true
                end
            end

            # Now install the RubyGems
            if !gems.empty?
                guess_gem_program

                cmdline = [Autobuild.tool('gem'), 'install']
                if Autoproj::OSDependencies.gem_with_prerelease
                    cmdline << "--prerelease"
                end
                cmdline.concat(gems)

                if gems_interaction(gems, cmdline, silent?)
                    Autobuild.progress "installing/updating RubyGems dependencies: #{gems.sort.join(", ")}"
                    Autobuild::Subprocess.run 'autoproj', 'osdeps', *cmdline
                    did_something = true
                end
            end

            did_something
        end
    end
end

