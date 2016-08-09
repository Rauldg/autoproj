require 'autoproj/test'

module Autoproj
    describe PackageSet do
        attr_reader :package_set, :raw_local_dir, :vcs
        before do
            ws_create
            @vcs = VCSDefinition.from_raw(type: 'local', url: '/path/to/set')
            @raw_local_dir = File.join(ws.root_dir, 'package_set')
            @package_set = PackageSet.new(
                ws, vcs, raw_local_dir: raw_local_dir)
        end

        it "is not a main package set" do
            refute package_set.main?
        end

        it "is local if its vcs is" do
            assert package_set.local?
            flexmock(package_set.vcs).should_receive(:local?).and_return(false)
            refute package_set.local?
        end

        it "is empty on construction" do
            assert package_set.empty?
        end

        describe ".name_of" do
            it "returns the package set name as present on disk if it is present" do
                FileUtils.mkdir_p File.join(ws.root_dir, 'package_set')
                File.open(File.join(package_set.raw_local_dir, 'source.yml'), 'w') do |io|
                    io.write YAML.dump(Hash['name' => 'test'])
                end
                assert_equal 'test', PackageSet.name_of(ws, vcs, raw_local_dir: raw_local_dir)
            end
            it "uses the VCS as name if the package set is not present" do
                assert_equal 'local:/path/to/set', PackageSet.name_of(ws, vcs, raw_local_dir: raw_local_dir)
            end
        end

        describe ".raw_local_dir_of" do
            it "returns the local path if the VCS is local" do
                assert_equal '/path/to/package_set', PackageSet.raw_local_dir_of(ws,
                    VCSDefinition.from_raw('type' => 'local', 'url' => '/path/to/package_set'))
            end
            it "returns a normalized subdirectory of the workspace's remotes dir the VCS is remote" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                repository_id = Autobuild.git(
                    'https://github.com/test/url',
                    branch: 'test_branch').repository_id
                path = PackageSet.raw_local_dir_of(ws, vcs)
                assert path.start_with?(ws.remotes_dir)
                assert_equal repository_id.gsub(/[^\w]/, '_'),
                    path[(ws.remotes_dir.size + 1)..-1]
            end
        end

        describe "initialize" do
            it "propagates the workspace's resolver setup" do
                resolver = package_set.os_package_resolver
                # Values are from Autoproj::Test#ws_create_os_package_resolver
                assert_equal [['test_os_family'], ['test_os_version']],
                    resolver.operating_system
                assert_equal 'os', resolver.os_package_manager
                assert_equal ws_package_managers.keys, resolver.package_managers
            end
        end
        describe "#present?" do
            it "returns false if the local dir does not exist" do
                refute package_set.present?
            end
            it "returns true if the local dir exists" do
                FileUtils.mkdir_p File.join(ws.root_dir, 'package_set')
                assert package_set.present?
            end
        end

        describe "#resolve_definition" do
            it "resolves a local package set relative to the config dir" do
                FileUtils.mkdir_p(dir = File.join(ws.config_dir, 'dir'))
                vcs, options = PackageSet.resolve_definition(ws, 'dir')
                assert_equal Hash[auto_imports: true], options
                assert vcs.local?
                assert_equal dir, vcs.url
            end
            it "resolves a local package set given in absolute" do
                FileUtils.mkdir_p(dir = File.join(ws.config_dir, 'dir'))
                vcs, options = PackageSet.resolve_definition(ws, dir)
                assert_equal Hash[auto_imports: true], options
                assert vcs.local?
                assert_equal dir, vcs.url
            end
            it "raises if given a relative path that does not exist" do
                e = assert_raises(ArgumentError) do
                    PackageSet.resolve_definition(ws, 'dir')
                end
                assert_equal "'dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end
            it "raises if given a full path that does not exist" do
                e = assert_raises(ArgumentError) do
                    PackageSet.resolve_definition(ws, '/full/dir')
                end
                assert_equal "'/full/dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end
        end
        
        describe "#repository_id" do
            it "returns the package set path if the set is local" do
                package_set = PackageSet.new(ws, VCSDefinition.from_raw('type' => 'local', 'url' => '/path/to/set'))
                assert_equal '/path/to/set', package_set.repository_id
            end
            it "returns the importer's repository_id if there is one" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                repository_id = Autobuild.git(
                    'https://github.com/test/url',
                    branch: 'test_branch').repository_id

                package_set = PackageSet.new(ws, vcs)
                assert_equal repository_id, package_set.repository_id
            end

            it "returns the vcs as string if the importer has no repository_id" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                importer = vcs.create_autobuild_importer
                flexmock(importer).should_receive(:respond_to?).with(:repository_id).and_return(false)
                flexmock(vcs).should_receive(:create_autobuild_importer).and_return(importer)
                package_set = PackageSet.new(ws, vcs, raw_local_dir: '/path/to/set')
                assert_equal vcs.to_s, package_set.repository_id
            end
        end

        describe "#normalize_vcs_list" do
            it "raises with a specific error message if the list is a hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', Hash.new)
                end
                assert_equal "wrong format for the version_control section of /path/to/file, you forgot the '-' in front of the package names", e.message
            end
            it "raises with a generic error message if the list is neither an array nor a hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', nil)
                end
                assert_equal "wrong format for the version_control section of /path/to/file",
                    e.message
            end

            it "converts a number to a string using convert_to_nth" do
                Hash[1 => '1st', 2 => '2nd', 3 => '3rd'].each do |n, string|
                    assert_equal string, package_set.number_to_nth(n)
                end
                assert_equal "25th", package_set.number_to_nth(25)
            end

            it "raises if the entry elements are not hashes" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', [nil])
                end
                assert_equal "wrong format for the 1st entry (nil) of the version_control section of /path/to/file, expected a package name, followed by a colon, and one importer option per following line", e.message
            end

            it "normalizes the YAML loaded if all a package keys are at the same level" do
                # - package_name:
                #   type: git
                #
                # is loaded as { 'package_name' => nil, 'type' => 'git' }
                assert_equal [['package_name', Hash['type' => 'git']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => nil, 'type' => 'git']
                        ])
            end

            it "normalizes the YAML loaded from a properly formatted source file" do
                # - package_name:
                #     type: git
                #
                # is loaded as { 'package_name' => { 'type' => 'git' } }
                assert_equal [['package_name', Hash['type' => 'git']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => Hash['type' => 'git']]
                        ])
            end

            it "accepts a package_name: none shorthand" do
                assert_equal [['package_name', Hash['type' => 'none']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => 'none']
                        ])
            end
            
            it "converts the package name into a regexp if it contains non-standard characters" do
                assert_equal [[/^test.*/, Hash['type' => 'none']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['test.*' => 'none']
                        ])
            end

            it "raises InvalidYAMLFormatting for a package name without a specification" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['test' => nil]])
                end
                assert_equal "expected 'test:' followed by version control options, but got nothing, in the 1st entry of the version_control section of /path/to/file", e.message
            end

            it "raises InvalidYAMLFormatting for an inconsistent formatted hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['test' => 'with_value', 'type' => 'git']])
                end
                assert_equal "cannot make sense of the 1st entry in the version_control section of /path/to/file: {\"test\"=>\"with_value\", \"type\"=>\"git\"}", e.message
            end

            it "raises for the shorthand for any other importer than 'none'" do
                e = assert_raises(ConfigError) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['package_name' => 'local']])
                end
                assert_equal "invalid VCS specification in the version_control section of /path/to/file: 'package_name: local'. One can only use this shorthand to declare the absence of a VCS with the 'none' keyword", e.message
            end
        end

        describe ".raw_description_file" do
            it "raises if the source.yml does not exist" do
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file('/path/to/package_set', package_set_name: 'name_of_package_set')
                end
                assert_equal "package set name_of_package_set present in /path/to/package_set should have a source.yml file, but does not",
                    e.message
            end
            it "handles empty files gracefully" do
                dir = make_tmpdir
                FileUtils.touch(File.join(dir, 'source.yml'))
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file(dir, package_set_name: 'name_of_package_set')
                end
                assert_equal "#{dir}/source.yml does not have a 'name' field", e.message
            end
            it "raises if the source.yml does not have a name field" do
                dir = make_tmpdir
                File.open(File.join(dir, 'source.yml'), 'w') do |io|
                    YAML.dump(Hash[], io)
                end
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file(dir, package_set_name: 'name_of_package_set')
                end
                assert_equal "#{dir}/source.yml does not have a 'name' field", e.message
            end
        end

        describe "raw_description_file" do
            it "raises InternalError if the package set's directory does not exist" do
                package_set = PackageSet.new(
                    ws, VCSDefinition.from_raw('type' => 'git', 'url' => 'https://url'),
                    raw_local_dir: '/path/to/package_set',
                    name: 'name_of_package_set')

                e = assert_raises(InternalError) do
                    package_set.raw_description_file
                end
                assert_equal "source git:https://url has not been fetched yet, cannot load description for it",
                    e.message
            end
            it "passes the package set's name to PackageSet.raw_description_file" do
                dir = make_tmpdir
                flexmock(PackageSet).should_receive(:raw_description_file).
                    with(dir, package_set_name: 'name_of_package_set').
                    once.pass_thru
                package_set = PackageSet.new(ws, VCSDefinition.from_raw('type' => 'local', 'url' => dir),
                                            name: 'name_of_package_set')
                e = assert_raises(ConfigError) do
                    package_set.raw_description_file
                end
                assert_equal "package set name_of_package_set present in #{dir} should have a source.yml file, but does not",
                    e.message
            end
        end
    end
end

