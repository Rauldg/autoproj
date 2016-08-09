require 'autoproj/test'
require 'autoproj/ops/configuration'

module Autoproj
    module Ops
        describe Configuration do
            describe "#sort_package_sets_by_import_order" do
                attr_reader :ops

                before do
                    ws = ws_create
                    @ops = Autoproj::Ops::Configuration.new(ws)
                end

                it "should handle standalone package sets that are both explicit and dependencies of other package sets gracefully (issue#30)" do
                    pkg_set0 = flexmock('set0', imports: [], explicit?: true)
                    pkg_set1 = flexmock('set1', imports: [pkg_set0], explicit?: true)
                    root_pkg_set = flexmock('root', imports: [pkg_set0, pkg_set1], explicit?: true)
                    assert_equal [pkg_set0, pkg_set1, root_pkg_set],
                        ops.sort_package_sets_by_import_order([pkg_set1, pkg_set0], root_pkg_set)
                end

                it "applies the package set overrides using the pkg_set:repository_id keys" do
                    package_set_dir = File.join(ws.root_dir, 'package_set')
                    root_package_set = ws.manifest.main_package_set
                    root_package_set.add_raw_imported_set VCSDefinition.from_raw('type' => 'local', 'url' => '/test')
                    root_package_set.add_overrides_entry 'pkg_set:local:/test', 'url' => package_set_dir
                    FileUtils.mkdir_p package_set_dir
                    File.open(File.join(package_set_dir, 'source.yml'), 'w') do |io|
                        YAML.dump(Hash['name' => 'imported_package_set'], io)
                    end
                    ops.load_and_update_package_sets(root_package_set)
                end
            end
        end
    end
end

