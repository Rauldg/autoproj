require 'autoproj/test'
require 'set'

module Autoproj
    describe Manifest do
        attr_reader :manifest
        before do
            ws_create
            @manifest = ws.manifest
        end

        describe "#add_package_to_layout" do
            it "raises if the package is not registered on the receiver" do
                package = Autobuild.cmake('test')
                assert_raises(UnregisteredPackage) do
                    manifest.add_package_to_layout(package)
                end
            end
            it "adds the package to an empty layout" do
                package = ws.define_package(:cmake, 'test')
                manifest.add_package_to_layout(package)
                assert_equal Set['test'], manifest.default_packages.each_source_package_name.to_set
            end
            it "adds the package to an existing layout" do
                p0 = ws.define_package(:cmake, 'test1')
                p1 = ws.define_package(:cmake, 'test2')
                manifest.add_package_to_layout(p0)
                manifest.add_package_to_layout(p1)
                assert_equal Set['test1', 'test2'], manifest.default_packages.each_source_package_name.to_set
            end
        end

        describe "ignored packages" do
            it "is initialized by the ignored_packages list in the manifest file" do
                manifest.initialize_from_hash('ignore_packages' => ['test'])
                package = ws.define_package :cmake, 'test'
                assert manifest.ignored?(package)
            end
            it "can clear the ignores specified in the manifest file" do
                manifest.initialize_from_hash('ignore_packages' => ['test'])
                package = ws.define_package :cmake, 'test'
                manifest.clear_ignored
                refute manifest.ignored?(package)
            end
            it "registers the package to be ignored" do
                package = ws.define_package :cmake, 'test'
                manifest.ignore_package package
                assert manifest.ignored?(package)
            end
            it "accepts a package name as well" do
                package = ws.define_package :cmake, 'test'
                manifest.ignore_package 'test'
                assert manifest.ignored?(package)
            end
            it "raises if the package is not part of self" do
                package = ws.define_package :cmake, 'test'
                assert_raises(UnregisteredPackage) do
                    Manifest.new(ws).ignore_package(package)
                end
                refute manifest.ignored?(package)
            end
            it "can register metapackages names" do
                package = ws.define_package :cmake, 'pkg'
                manifest.metapackage 'test', 'pkg'
                manifest.ignore_package 'test'
                assert manifest.ignored?(package)
            end
            it "raises PackageNotFound if a package name cannot be resolved into a package object" do
                assert_raises(PackageNotFound) do
                    manifest.ignored?('test')
                end
            end
            it "returns false for a package that is not ignored" do
                manifest.ignore_package 'pkg'
                ws.define_package :cmake, 'test'
                assert !manifest.ignored?('test')
            end
            it "enumerates the autobuild packages that are ignored" do
                manifest.ignore_package 'pkg'
                pkg = ws.define_package :cmake, 'pkg'
                assert_equal [pkg.autobuild], manifest.each_ignored_package.to_a
            end
            it "clears the existing ignores" do
                ws.define_package :cmake, 'pkg'
                manifest.ignore_package 'pkg'
                manifest.clear_ignored
                assert !manifest.ignored?('pkg')
            end
        end

        describe "excluded packages" do
            it "is initialized by a package name listed in the exclude_packages list in the manifest file" do
                manifest.initialize_from_hash('exclude_packages' => ['test'])
                package = ws.define_package :cmake, 'test'
                assert manifest.excluded?(package)
                assert manifest.excluded_in_manifest?(package)
                assert_equal "test is listed in the exclude_packages section of the manifest",
                    manifest.exclusion_reason(package)
            end
            it "is initialized by a package set name listed in the exclude_packages list in the manifest file" do
                manifest.initialize_from_hash('exclude_packages' => ['test'])
                package = ws.define_package :cmake, 'pkg'
                manifest.metapackage 'test', 'pkg'
                assert manifest.excluded?(package)
                assert manifest.excluded_in_manifest?(package)
                assert_equal "test is a metapackage listed in the exclude_packages section of the manifest, and it includes pkg",
                    manifest.exclusion_reason(package)
            end
            it "can clear the exclusions specified in the manifest file" do
                manifest.initialize_from_hash('exclude_packages' => ['test'])
                package = ws.define_package :cmake, 'test'
                manifest.clear_exclusions
                refute manifest.excluded?(package)
                refute manifest.excluded_in_manifest?(package)
                refute manifest.exclusion_reason(package)
            end
            it "registers the package to be excluded" do
                package = ws.define_package :cmake, 'test'
                manifest.exclude_package package, "for testing"
                assert manifest.excluded?(package)
                refute manifest.excluded_in_manifest?(package)
                assert_equal "for testing", manifest.exclusion_reason(package)
            end
            it "accepts a package name as well" do
                ws.define_package :cmake, 'test'
                manifest.exclude_package 'test', "for testing"
                assert manifest.excluded?('test')
                refute manifest.excluded_in_manifest?('test')
                assert_equal "for testing", manifest.exclusion_reason('test')
            end
            it "raises if the package is not part of self" do
                package = ws.define_package :cmake, 'test'
                assert_raises(UnregisteredPackage) do
                    Manifest.new(ws).exclude_package(package, "for testing")
                end
                refute manifest.excluded?(package)
            end
            it "can register metapackages names" do
                package = ws.define_package :cmake, 'pkg'
                manifest.metapackage 'test', 'pkg'
                manifest.exclude_package 'test', "for testing"
                assert manifest.excluded?(package)
                refute manifest.excluded_in_manifest?(package)
                assert_equal "test is an excluded metapackage, and it includes pkg: for testing",
                    manifest.exclusion_reason(package)
            end
            it "raises PackageNotFound if a package name cannot be resolved into a package object" do
                assert_raises(PackageNotFound) do
                    manifest.excluded?('test')
                end
            end
            it "returns false for a package that is not excluded" do
                manifest.exclude_package 'pkg', "for testing"
                ws.define_package :cmake, 'test'
                assert !manifest.excluded?('test')
            end
            it "enumerates the autobuild packages that are excluded" do
                manifest.exclude_package 'pkg', "for testing"
                pkg = ws.define_package :cmake, 'pkg'
                assert_equal [pkg.autobuild], manifest.each_excluded_package.to_a
            end
            it "clears the existing exclusions" do
                ws.define_package :cmake, 'pkg'
                manifest.exclude_package 'pkg', "for testing"
                manifest.clear_exclusions
                assert !manifest.excluded?('pkg')
            end
        end

        describe "#metapackage" do
            it "registers the package given by name" do
                package = ws.define_package :cmake, 'pkg'
                meta = manifest.metapackage 'test', 'pkg'
                assert meta.include?(package)
            end
            it "expands a metapackage given as argument" do
                package = ws.define_package :cmake, 'pkg'
                manifest.metapackage 'parent', 'pkg'
                meta = manifest.metapackage 'test', 'parent'
                assert meta.include?(package)
            end
            it "raises if a package cannot be resolved" do
                e = assert_raises(PackageNotFound) do
                    manifest.metapackage 'test', 'does_not_exist'
                end
                assert_equal "cannot find a package called does_not_exist", e.message
            end
            it "raises if a package is resolved as an osdep" do
                ws_define_osdep_entries 'osdep' => Hash['test_os_family' => 'pkg']
                e = assert_raises(ArgumentError) do
                    manifest.metapackage 'test', 'osdep'
                end
                assert_equal "cannot specify the osdep osdep as an element of a metapackage", e.message
            end
        end

        describe "#resolve_package_name" do
            it "resolves source packages" do
                manifest.register_package(Autobuild::Package.new('test'))
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages" do
                manifest.os_package_resolver.merge OSPackageResolver.new('test' => Hash['test_os_family' => 'bla'])
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides on OSes where the package is not available" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                manifest.add_osdeps_overrides 'test', package: 'test_src'
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                assert_equal [[:package, 'test_src']], manifest.resolve_package_name('test')
            end
            it "resolves to the OS package if both an OS and source package are available at the same time" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "automatically resolves OS packages into a source package with the same name if the package is not available" do
                manifest.register_package(Autobuild::Package.new('test'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides if the override is forced" do
                manifest.register_package(Autobuild::Package.new('test'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                manifest.add_osdeps_overrides 'test', force: true
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides if the override is forced" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                manifest.add_osdeps_overrides 'test', package: 'test_src', force: true
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                assert_equal [[:package, 'test_src']], manifest.resolve_package_name('test')
            end
            it "resolves an OS package that is explicitely marked as ignored" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::IGNORE)
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "raises if a package is undefined" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::NO_PACKAGE)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is not an osdep and it cannot be resolved as a source package/, e.message)
            end
            it "raises if a package is defined as an osdep but it is not available on the local operating system" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is an osdep, but it is not available for this operating system and it cannot be resolved as a source package/, e.message)
            end
            it "raises if a package is defined as an osdep but it is explicitely marked as non existent" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::NONEXISTENT)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is an osdep, but it is explicitely marked as 'nonexistent' for this operating system and it cannot be resolved as a source package/, e.message)
            end
        end

        describe "#layout_packages" do
            attr_reader :meta
            before do
                ws_define_package :cmake, 'test'
                @meta = manifest.metapackage 'pkg', 'test'
            end

            it "expands metapackages" do
                manifest.add_metapackage_to_layout meta
                selection = manifest.layout_packages
                assert_equal ['test'], selection.each_source_package_name.to_a
            end

            it "propagates weak selections" do
                pkg = ws_define_package :cmake, 'other_test'
                meta.add(pkg.autobuild)
                meta.weak_dependencies = true
                manifest.add_metapackage_to_layout meta
                manifest.exclude_package('test', 'for testing')
                selection = manifest.layout_packages
                assert_equal ['other_test'], selection.each_source_package_name.to_a
            end

            it "resolves and marks osdeps properly" do
                ws_define_osdep_entries 'osdep_package' => Hash['test_os_family' => 'pkg']
                manifest.initialize_from_hash('layout' => Array['osdep_package'])
                sel = manifest.layout_packages
                assert_equal ['osdep_package'], sel.each_osdep_package_name.to_a
            end

            it "raises if a unknown package is found" do
                manifest.initialize_from_hash('layout' => Array['does_not_exist'])
                e = assert_raises(PackageNotFound) do
                    manifest.layout_packages
                end
                assert_equal "does_not_exist, which is selected in the layout, is unknown: cannot resolve does_not_exist: does_not_exist is not an osdep and it cannot be resolved as a source package", e.message
            end
        end

        describe "#all_selected_packages" do
            it "returns all the layout packages as well as their dependencies" do
                ws_define_osdep_entries 'dependency_os_package' => Hash['test_os_family' => 'pkg']
                ws_add_osdep_entries_to_layout 'direct_os_package' => Hash['test_os_family' => 'pkg']
                ws_define_package :cmake, 'dependency_package'
                ws_add_package_to_layout :cmake, 'direct_package' do |pkg|
                    pkg.depends_on 'dependency_package'
                    pkg.depends_on 'dependency_os_package'
                end

                assert_equal Set['direct_package', 'dependency_package', 'dependency_os_package', 'direct_os_package'],
                    manifest.all_selected_packages.to_set
            end
        end

        describe "#default_packages" do
            it "returns the set of packages directly selected by the manifest" do
                ws_define_osdep_entries 'dependency_os_package' => Hash['test_os_family' => 'pkg']
                ws_add_osdep_entries_to_layout 'direct_os_package' => Hash['test_os_family' => 'pkg']
                ws_define_package :cmake, 'dependency_package'
                ws_add_package_to_layout :cmake, 'direct_package' do |pkg|
                    pkg.depends_on 'dependency_package'
                    pkg.depends_on 'dependency_os_package'
                end

                assert_equal Set['direct_package', 'direct_os_package'],
                    manifest.default_packages.each_package_name.to_set
            end

            it "returns the set of defined source packages if no layout is given" do
                ws_define_osdep_entries 'dependency_os_package' => Hash['test_os_family' => 'pkg']
                ws_define_package :cmake, 'dependency_package'
                ws_define_package :cmake, 'direct_package' do |pkg|
                    pkg.depends_on 'dependency_package'
                    pkg.depends_on 'dependency_os_package'
                end

                assert_equal Set['direct_package', 'dependency_package'],
                    manifest.default_packages.each_package_name.to_set
            end
        end

        describe "#normalized_layout" do
            it "maps the package name to the layout level" do
                manifest.initialize_from_hash(
                    'layout' => Array[
                        'root_pkg',
                        Hash['sub' => Array[
                            'child_pkg'
                        ]]
                    ])
                assert_equal Hash['root_pkg' => '/', 'child_pkg' => '/sub/'],
                    manifest.normalized_layout
            end
        end

        describe "#importer_definition_for" do
            attr_reader :root_pkg_set, :base_pkg_set, :overrides_pkg_set
            attr_reader :package
            before do
                @root_pkg_set      = ws_define_package_set "root" 
                @base_pkg_set      = ws_define_package_set "base" 
                @overrides_pkg_set = ws_define_package_set "overrides"

                @package = ws_define_package(:cmake, 'test', package_set: base_pkg_set)
            end

            it "returns the VCS definition from the package's own package set" do
                ws_define_package_vcs(package, Hash[type: 'git', url: 'https://github.com/test'])
                vcs = manifest.importer_definition_for(package)
                assert_equal 'git', vcs.type
                assert_equal 'https://github.com/test', vcs.url
            end

            describe "handling of overrides" do
                before do
                    ws_define_package_vcs(
                        package,
                        Hash[type: 'git', url: 'https://github.com/test'])
                    ws_define_package_overrides(
                        package, overrides_pkg_set,
                        Hash[type: 'git', url: 'https://github.com/test/fork', branch: 'wip'])
                end
                it "applies the overrides from the following package sets" do
                    vcs = manifest.importer_definition_for(package)
                    assert_equal 'git', vcs.type
                    assert_equal 'https://github.com/test/fork', vcs.url
                    assert_equal 'wip', vcs.options[:branch]
                end
                it "does not apply the overrides if the mainline is defined as the package's own package set" do
                    vcs = manifest.importer_definition_for(package, mainline: base_pkg_set)
                    assert_equal 'git', vcs.type
                    assert_equal 'https://github.com/test', vcs.url
                end
                it "does not apply the overrides if the mainline is defined as a package set before the package's own" do
                    vcs = manifest.importer_definition_for(package, mainline: root_pkg_set)
                    assert_equal 'git', vcs.type
                    assert_equal 'https://github.com/test', vcs.url
                end
                it "only applies overrides up to the specified mainline" do
                    further_pkg_set = ws_define_package_set "further"
                    ws_define_package_overrides(
                        package, further_pkg_set,
                        Hash[type: 'local', url: '/local/path'])
                    vcs = manifest.importer_definition_for(package, mainline: overrides_pkg_set)
                    assert_equal 'git', vcs.type
                    assert_equal 'https://github.com/test/fork', vcs.url
                    assert_equal 'wip', vcs.options[:branch]
                end
            end
        end

        describe "#expand_package_selection" do
            it "selects a source package by its exact name" do
                ws_add_package_to_layout :cmake, 'test/package'
                sel, nonresolved = manifest.expand_package_selection(['test/package'])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for('test/package')
            end
            it "selects a source package by a partial name" do
                ws_add_package_to_layout :cmake, 'test/package'
                sel, nonresolved = manifest.expand_package_selection(['pack'])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for('pack')
            end
            it "restricts a name selection to the selected packages" do
                ws_add_package_to_layout :cmake, 'test/package'
                ws_define_package :cmake, 'test/package_plugin'
                sel, nonresolved = manifest.expand_package_selection(['package'])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for('package')
            end
            it "does select non-layout packages if there are no layout packages matching" do
                ws_clear_layout
                ws_define_package :cmake, 'test/package_plugin'
                sel, nonresolved = manifest.expand_package_selection(['package'])
                assert nonresolved.empty?
                assert_equal Set['test/package_plugin'], sel.match_for('package')
            end
            it "returns only the exact name match even if there are non-exact ones" do
                ws_add_package_to_layout :cmake, 'test/package'
                ws_add_package_to_layout :cmake, 'test/package_plugin'
                sel, nonresolved = manifest.expand_package_selection(['test/package'])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for('test/package')
            end
            it "selects a source package by exact srcdir" do
                pkg = ws_add_package_to_layout :cmake, 'test/package'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package")
                
                dir = pkg.autobuild.srcdir
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for(dir)
            end
            it "selects a source package by a subdirectory of the srcdir" do
                pkg = ws_add_package_to_layout :cmake, 'test/package'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package")

                dir = File.join(pkg.autobuild.srcdir, 'subdir')
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for(dir)
                assert_equal ['test/package'], sel.each_source_package_name.to_a
                assert_equal [], sel.each_osdep_package_name.to_a
            end
            it "selects an osdeps package by name" do
                ws_define_osdep_entries 'osdep' => 'ignore'
                sel, nonresolved = manifest.expand_package_selection(['osdep'])
                assert nonresolved.empty?
                assert_equal Set['osdep'], sel.match_for('osdep')
                assert_equal [], sel.each_source_package_name.to_a
                assert_equal ['osdep'], sel.each_osdep_package_name.to_a
            end
            it "restricts the selection by srcdir to the exact match" do
                pkg = ws_add_package_to_layout :cmake, 'test/package'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package")
                pkg = ws_add_package_to_layout :cmake, 'test/package_plugin'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package_plugin")
                dir = File.join(ws.root_dir, "test", 'package')
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for(dir)
                assert_equal ['test/package'], sel.each_source_package_name.to_a
                assert_equal [], sel.each_osdep_package_name.to_a
            end
            it "selects multiple packages by srcdir" do
                pkg = ws_add_package_to_layout :cmake, 'test/package'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package")
                pkg = ws_add_package_to_layout :cmake, 'test/package_plugin'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package_plugin")
                dir = File.join(ws.root_dir, "test")
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert nonresolved.empty?
                assert_equal Set['test/package', 'test/package_plugin'], sel.match_for(dir)
            end
            it "prefers layout packages over non-selected ones" do
                pkg = ws_add_package_to_layout :cmake, 'test/package'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package")
                pkg = ws_define_package :cmake, 'test/package_plugin'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package_plugin")
                dir = File.join(ws.root_dir, "test")
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert nonresolved.empty?
                assert_equal Set['test/package'], sel.match_for(dir)
            end
            it "does not select non-layout packages by srcdir" do
                ws_clear_layout
                pkg = ws_define_package :cmake, 'test/package_plugin'
                pkg.autobuild.srcdir = File.join(ws.root_dir, "test", "package_plugin")
                dir = File.join(ws.root_dir, "test")
                sel, nonresolved = manifest.expand_package_selection([dir])
                assert_equal [dir], nonresolved
                assert_equal Set[], sel.match_for(dir)
            end
        end

        describe "#load_package_manifest" do
            attr_reader :pkg, :pkg_set
            before do
                @pkg_set = ws_define_package_set 'pkg_set',
                    raw_local_dir: File.join(ws.root_dir, 'pkg_set')
                @pkg = ws_add_package_to_layout :cmake, 'test',
                    package_set: pkg_set
            end
            it "loads the package's manifest.xml file if present" do
                package_manifest = PackageManifest.new(pkg.autobuild)
                flexmock(File).should_receive(:file?).
                    with(manifest_path = File.join(pkg.autobuild.srcdir, "manifest.xml")).
                    and_return(true)
                flexmock(PackageManifest).should_receive(:load).
                    with(pkg.autobuild, manifest_path).
                    and_return(package_manifest)
                assert_same package_manifest, manifest.load_package_manifest(pkg)
                assert_same package_manifest, pkg.autobuild.description
            end
            it "falls back on the manifest in the package set if present" do
                package_manifest = PackageManifest.new(pkg.autobuild)
                flexmock(File).should_receive(:file?).
                    with(File.join(pkg.autobuild.srcdir, "manifest.xml")).
                    and_return(false)
                flexmock(File).should_receive(:file?).
                    with(manifest_path = File.join(pkg_set.raw_local_dir, 'manifests', "test.xml")).
                    and_return(true)
                flexmock(PackageManifest).should_receive(:load).
                    with(pkg.autobuild, manifest_path).
                    and_return(package_manifest)
                assert_same package_manifest, manifest.load_package_manifest(pkg)
                assert_same package_manifest, pkg.autobuild.description
            end
            it "warns if no package set can be found" do
                flexmock(File).should_receive(:file?).and_return(false)
                flexmock(Autoproj).should_receive(:warn).
                    with("test from pkg_set does not have a manifest").
                    once
                assert manifest.load_package_manifest(pkg).null?
            end
            it "applies the dependencies from the manifest to the package" do
                xml = REXML::Document.new("<package><depend package=\"dependency\" /></package>")
                package_manifest = PackageManifest.new(pkg.autobuild, xml)
                flexmock(File).should_receive(:file?).and_return(true)
                flexmock(PackageManifest).should_receive(:load).and_return(package_manifest)
                ws_define_package :cmake, 'dependency'
                flexmock(pkg.autobuild).should_receive(:depends_on).
                    with('dependency').once.pass_thru
                manifest.load_package_manifest(pkg)
            end
            it "applies the optional dependencies from the manifest to the package" do
                xml = REXML::Document.new("<package><depend_optional package=\"dependency\" /></package>")
                package_manifest = PackageManifest.new(pkg.autobuild, xml)
                flexmock(File).should_receive(:file?).and_return(true)
                flexmock(PackageManifest).should_receive(:load).and_return(package_manifest)
                ws_define_package :cmake, 'dependency'
                flexmock(pkg.autobuild).should_receive(:optional_dependency).
                    with('dependency').once.pass_thru
                manifest.load_package_manifest(pkg)
            end
            it "adds a reference to the manifest file in the error message if it refers to a package that does not exist" do
                xml = REXML::Document.new("<package><depend package=\"dependency\" /></package>")
                package_manifest = PackageManifest.new(pkg.autobuild, xml)
                flexmock(File).should_receive(:file?).and_return(true)
                flexmock(PackageManifest).should_receive(:load).and_return(package_manifest)
                e = assert_raises(ConfigError) do
                    manifest.load_package_manifest(pkg)
                end
                assert_equal "manifest #{File.join(ws.root_dir, 'test', 'manifest.xml')} of test from pkg_set lists 'dependency' as dependency, but it is neither a normal package nor an osdeps package. osdeps reports: cannot resolve dependency: dependency is not an osdep and it cannot be resolved as a source package", e.message
            end
        end
    end
end

