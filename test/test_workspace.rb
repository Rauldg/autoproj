require 'autoproj/test'
require 'autoproj/autobuild'
require 'rubygems/server'

module Autoproj
    describe Workspace do
        describe "#setup" do
            attr_reader :ws
            before do
                @ws = ws_create
            end

            it "rewrite the shims to fix any discrepancy" do
                flexmock(Ops::Install).should_receive(:rewrite_shims).
                    with(File.join(ws.root_dir, ".autoproj", 'bin'),
                         ws.config.ruby_executable,
                         File.join(ws.root_dir, ".autoproj", 'Gemfile'),
                         ws.config.gems_gem_home).
                     once
                ws.setup
            end
        end

        describe "#load_package_sets" do
            attr_reader :test_dir, :test_autoproj_dir, :workspace
            before do
                @test_dir = make_tmpdir
                @test_autoproj_dir = File.join(@test_dir, 'autoproj')
                FileUtils.mkdir_p test_autoproj_dir
                FileUtils.touch File.join(test_autoproj_dir, 'manifest')
                FileUtils.touch File.join(test_autoproj_dir, 'test.autobuild')
                File.open(File.join(test_autoproj_dir, 'test.osdeps'), 'w') do |io|
                    YAML.dump(Hash.new, io)
                end
                File.open(File.join(test_autoproj_dir, 'overrides.yml'), 'w') do |io|
                    YAML.dump(Hash['version_control' => Array.new, 'overrides' => Array.new], io)
                end
                @workspace = Workspace.new(test_dir)
                workspace.os_package_resolver.operating_system = [['debian', 'tests'], ['test_version']]
                workspace.load_config
            end

            def add_in_osdeps(entry)
                test_osdeps = File.join(test_autoproj_dir, 'test.osdeps')
                current = YAML.load(File.read(test_osdeps))
                File.open(test_osdeps, 'w') do |io|
                    YAML.dump(current.merge!(entry), io)
                end
            end

            def add_in_packages(lines)
                File.open(File.join(test_autoproj_dir, 'test.autobuild'), 'a') do |io|
                    io.puts lines
                end
            end

            def add_version_control(package_name, type: 'local', url: package_name, **vcs)
                overrides_yml = YAML.load(File.read(File.join(test_autoproj_dir, 'overrides.yml')))
                overrides_yml['version_control'] << Hash[
                    package_name =>
                        vcs.merge(type: type, url: url)
                ]
                File.open(File.join(test_autoproj_dir, 'overrides.yml'), 'w') do |io|
                    io.write YAML.dump(overrides_yml)
                end
            end

            it "loads the osdep files" do
                flexmock(workspace.manifest.each_package_set.first).
                    should_receive(:load_osdeps).with(File.join(test_autoproj_dir, 'test.osdeps')).
                    at_least.once.and_return(osdep = flexmock)
                flexmock(workspace.os_package_resolver).
                    should_receive(:merge).with(osdep).at_least.once

                workspace.load_package_sets
            end
            it "excludes osdeps that are not available locally" do
                add_in_osdeps Hash['test' => 'nonexistent']
                workspace.load_package_sets
                assert workspace.manifest.excluded?('test')
            end
            it "does not exclude osdeps for which a source package with the same name exists" do
                add_in_osdeps Hash['test' => 'nonexistent']
                add_in_packages 'cmake_package "test"'
                add_version_control 'test'
                workspace.load_package_sets
                refute workspace.manifest.excluded?('test')
            end
            it "does not exclude osdeps for which an osdep override exists" do
                add_in_osdeps Hash['test' => 'nonexistent']
                add_in_packages 'cmake_package "mapping_test"'
                add_version_control 'mapping_test'
                add_in_packages 'Autoproj.add_osdeps_overrides "test", package: "mapping_test"'
                workspace.load_package_sets
                refute workspace.manifest.excluded?('test')
            end
        end

        describe "update_autoproj" do
            before do
                skip "long test" if skip_long_tests?
                prepare_fixture_gem_home
                start_gem_server
            end

            it "updates and restarts autoproj if a new version is available" do
                gems_path = make_tmpdir

                # First, we need to package autoproj as-is so that we can
                # install while using the gem server
                capture_subprocess_io do
                    system("rake", "build")
                    Bundler.clean_system(Hash['GEM_HOME' => fixture_gem_home], Ops::Install.guess_gem_program, 'install', '--no-document', File.join('pkg', "autoproj-#{VERSION}.gem"))
                end

                autobuild_full_path  = find_gem_dir('autobuild').full_gem_path
                install_dir, _ = invoke_test_script(
                    'install.sh', "--gems-path=#{gems_path}", '--gem-source', 'http://localhost:8808',
                    gemfile_source: "source 'http://localhost:8808'\ngem 'autoproj', '>= 2.0.0.a'\ngem 'autobuild', path: '#{autobuild_full_path}'")

                # We create a fake high-version gem and put it in the
                # vendor/cache (since we rely on a self-started server to serve
                # our gems)
                capture_subprocess_io do
                    system(Hash['__AUTOPROJ_TEST_FAKE_VERSION' => "2.99.99"], "rake", "build")
                    Bundler.clean_system(Hash['GEM_HOME' => fixture_gem_home], Ops::Install.guess_gem_program, 'install', '--no-document', File.join('pkg', 'autoproj-2.99.99.gem'))
                end

                result = nil
                stdout, stderr = capture_subprocess_io do
                    result = Bundler.clean_system(
                        File.join('.autoproj', 'bin', 'autoproj'), 'update', '--autoproj',
                        chdir: install_dir)
                end
                if !result
                    puts stdout
                    puts stderr
                    flunk("autoproj update --autoproj terminated")
                end
                assert_match(/autoproj has been updated/, stdout)
            end
        end

        describe ".from_dir" do
            def make_v1_workspace
                workspace_dir = make_tmpdir
                FileUtils.mkdir_p File.join(workspace_dir, 'autoproj')
                workspace_dir
            end
            def make_v2_workspace
                workspace_dir = make_tmpdir
                FileUtils.mkdir_p File.join(workspace_dir, '.autoproj')
                FileUtils.touch File.join(workspace_dir, '.autoproj', 'config.yml')
                workspace_dir
            end

            it "returns the path to the enclosing workspace" do
                workspace_dir = make_v2_workspace
                FileUtils.mkdir_p(test_dir = File.join(workspace_dir, 'test'))
                assert_equal workspace_dir, Workspace.from_dir(test_dir).root_dir
                assert_equal workspace_dir, Workspace.from_dir(workspace_dir).root_dir
            end

            it "raises OutdatedWorkspace if called within a v1 workspace" do
                workspace_dir = make_v1_workspace
                FileUtils.mkdir_p(test_dir = File.join(workspace_dir, 'test'))
                assert_raises(OutdatedWorkspace) do
                    Workspace.from_dir(test_dir)
                end
                assert_raises(OutdatedWorkspace) do
                    Workspace.from_dir(workspace_dir)
                end
            end
        end

        describe "#all_os_packages" do
            it "returns the list of all osdeps that are needed by the current workspace state" do
                ws_create
                ws_define_osdep_entries 'os_pkg' => Hash['os' => 'os_pkg_test']
                ws_define_osdep_entries 'os_indep_pkg' => Hash['os_indep' => 'os_indep_pkg_test']
                ws_define_osdep_entries 'not_used' => Hash['os_indep' => 'not_used']
                ws_add_package_to_layout :cmake, :test do |pkg|
                    pkg.depends_on 'os_pkg'
                    pkg.depends_on 'os_indep_pkg'
                end
                assert_equal Set['os_pkg', 'os_indep_pkg'], ws.all_os_packages.to_set
            end
        end

        describe "#export_env_sh" do
            attr_reader :pkg0, :pkg1, :env
            before do
                ws_create
                @pkg0         = ws_add_package_to_layout :cmake, :pkg0
                @pkg1         = ws_define_package :cmake, :pkg1
                flexmock(ws.env).should_receive(:dup).once.and_return(@env = flexmock)
            end
            it "aggregates the environment of all the selected packages" do
                flexmock(pkg0.autobuild).should_receive(:apply_env).with(env).once.globally.ordered
                flexmock(pkg1.autobuild).should_receive(:apply_env).with(env).never
                env.should_receive(:export_env_sh).once.globally.ordered
                ws.export_env_sh
            end
            it "ignores OS dependencies" do
                ws_define_osdep_entries 'root_osdep' => 'ignore'
                ws_define_osdep_entries 'dep_osdep' => 'ignore'
                pkg0.autobuild.depends_on 'dep_osdep'

                flexmock(pkg0.autobuild).should_receive(:apply_env).with(env).once.globally.ordered
                env.should_receive(:export_env_sh).once.globally.ordered
                ws.export_env_sh
            end
        end
    end
end

