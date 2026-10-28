#!/usr/bin/env python3
"""The app extensions a Flutter app's Runner embeds, as a SwiftPM package to build.

  gen-extensions.py <flutter app dir> <output package dir> <configuration>

Reads the extension targets the Runner's dependencies reach (productType
`app-extension`, as xcodeproj2xtool's extension_targets finds them) out of
Runner.xcodeproj and writes:

  Package.swift        one executable target per extension, linked the way
                       Xcode links an extension: the entry point is
                       _NSExtensionMain (Foundation provides it) and the
                       rpaths reach the app's Frameworks
  Sources/<name>/      symlinks to the target's sources — its Sources phase
                       plus, for Xcode 16 synchronized folders, the folder's
                       files minus its membership exceptions
                       (xcodeproj2xtool's plan_target_files)
  <name>-Info.plist    the Info.plist GENERATE_INFOPLIST_FILE = YES produces,
                       merged with the target's INFOPLIST_FILE
  plan.json            per extension: bundle id, minimum iOS, asset catalogs,
                       string catalogs and loose resources, for build.sh to
                       assemble into PlugIns/<name>.appex

Versions come from the target's own MARKETING_VERSION and
CURRENT_PROJECT_VERSION, as Xcode writes them; asc.py stamp aligns them with
the app's for the App Store path (ITMS-90473). An extension whose settings
leave a $(VAR) unresolved in the bundle id or whose INFOPLIST_FILE is missing
stops the run: a build with a made-up bundle id would ship a widget the app
cannot talk to. An extension with no Swift sources is skipped with a warning,
as xcodeproj2xtool skips it. Extensions needing packages of their own are not
supported: their build fails on the unresolved imports.

Self-test: `gen-extensions.py --self-test` builds a synthetic project in a
temporary directory (a synchronized folder with an Info.plist exception, one
extension, one extension without Swift sources) and checks the plan.
"""
import json
import os
import plistlib
import re
import shutil
import sys
import tempfile

import xcode_settings
# xcode_settings puts the repo's tools/ on sys.path and reads the same parser.
import xcodeproj2xtool  # noqa: E402


def settings_value(settings, name, ext):
    """A setting that must resolve: a leftover $(VAR) would build a lie."""
    value = settings.value(name)
    if "$(" in value or not value:
        sys.exit(f"error: extension {ext}: {name} does not resolve "
                 f"({value or 'unset'}); a made-up value would ship a broken extension")
    return value


def extension_info_plist(settings, gen, name, bundle_id, min_ios):
    """The plist GENERATE_INFOPLIST_FILE = YES writes, plus the target's own."""
    generated = {
        "CFBundleDevelopmentRegion": gen.project.get("developmentRegion") or "en",
        "CFBundleExecutable": settings.value("EXECUTABLE_NAME") or name,
        "CFBundleIdentifier": bundle_id,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": settings.value("PRODUCT_NAME") or name,
        # Xcode's value for an app extension (XPC!); the installer refuses an
        # .appex whose package type says anything else ("illegal value for
        # the CFBundlePackageType key: XPC", ditto APPL).
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": settings.value("MARKETING_VERSION") or "1.0",
        "CFBundleVersion": settings.value("CURRENT_PROJECT_VERSION") or "1",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": min_ios,
    }
    display = settings.value("INFOPLIST_KEY_CFBundleDisplayName")
    if display:
        generated["CFBundleDisplayName"] = display
    families = settings.value("TARGETED_DEVICE_FAMILY")
    if families:
        generated["UIDeviceFamily"] = [int(f) for f in families.split(",") if f.strip().isdigit()]
    info = {}
    source = settings.value("INFOPLIST_FILE")
    if source:
        path = os.path.join(settings.builtin["PROJECT_DIR"], source)
        if not os.path.isfile(path):
            sys.exit(f"error: extension {name}: INFOPLIST_FILE {source} does not exist")
        with open(path, "rb") as f:
            info = plistlib.load(f)
    if (settings.value("GENERATE_INFOPLIST_FILE") or "").upper() == "YES":
        info.update(generated)
    else:
        # A static plist: Xcode still stamps these from the build, whatever
        # the plist itself says or omits.
        for key in ("CFBundleExecutable", "CFBundleIdentifier", "CFBundleName",
                    "CFBundleShortVersionString", "CFBundleVersion",
                    "CFBundleSupportedPlatforms", "MinimumOSVersion"):
            info.setdefault(key, generated[key])
    return info


def version_key(version):
    return [int(x) for x in re.findall(r"\d+", version)] or [0]


def plan(app, out_dir, configuration):
    ios_dir = os.path.join(app, "ios")
    gen = xcodeproj2xtool.Generator(os.path.join(ios_dir, "Runner.xcodeproj"), "Runner")
    app_oid, _app_target = gen.pick_target()
    app_min = xcode_settings.Settings(ios_dir, configuration, "Runner") \
        .value("IPHONEOS_DEPLOYMENT_TARGET") or "13.0"

    extensions = []
    platform = app_min

    def materialize(symlinks):
        for link, dest in symlinks:
            lpath = os.path.join(out_dir, link)
            os.makedirs(os.path.dirname(lpath), exist_ok=True)
            if os.path.lexists(lpath):
                continue
            os.symlink(os.path.relpath(os.path.join(gen.proj_dir, dest),
                                       os.path.dirname(lpath)), lpath)

    for ext_oid, ext in gen.extension_targets(app_oid):
        name = ext["name"]
        settings = xcode_settings.Settings(ios_dir, configuration, name)
        symlinks, _excludes, resources, swift_rels = gen.plan_target_files(ext_oid, ext)
        if not swift_rels:
            gen.warn(f"extension {name} has no Swift sources; skipped")
            continue
        materialize(symlinks)
        bundle_id = settings_value(settings, "PRODUCT_BUNDLE_IDENTIFIER", name)
        min_ios = settings.value("IPHONEOS_DEPLOYMENT_TARGET") or app_min
        if version_key(min_ios) < version_key(platform):
            platform = min_ios
        root = os.path.join(out_dir, "Sources", name)
        assets, strings, loose = [], [], []
        for _kind, rel in resources:
            if any(part.startswith(".") for part in rel.split(os.sep)):
                continue  # .DS_Store and friends: junk Xcode never ships
            path = os.path.join(root, rel)
            if not os.path.exists(path):
                gen.warn(f"extension {name}: resource {rel} is not on disk; skipped")
            elif rel.endswith(".xcassets"):
                assets.append(path)
            elif rel.endswith(".xcstrings"):
                strings.append(path)
            else:
                loose.append([path, rel.replace(os.sep, "/")])
        info = extension_info_plist(settings, gen, name, bundle_id, min_ios)
        info_path = os.path.join(out_dir, f"{name}-Info.plist")
        with open(info_path, "wb") as f:
            plistlib.dump(info, f)
        extensions.append({
            "name": name,
            "bundle_id": bundle_id,
            "min_ios": min_ios,
            "assets": assets,
            "strings": strings,
            "resources": loose,
            "info_plist": info_path,
        })

    target_blocks = []
    for ext in extensions:
        target_blocks.append(f"""    .executableTarget(
      name: {xcodeproj2xtool.sw_sy(ext["name"])},
      swiftSettings: [.unsafeFlags(["-parse-as-library"])],
      linkerSettings: [
        .linkedFramework("Foundation"),
        .unsafeFlags([
          // The entry point of every app extension: Foundation implements
          // _NSExtensionMain, which bootstraps the extension runtime.
          "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../Frameworks",
          "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
        ]),
      ]
    ),
""")
    manifest = f"""// swift-tools-version: 5.9
// Generated by gen-extensions.py from ios/Runner.xcodeproj.
// Regenerate (rerun build.sh) after changing the Xcode project.
import PackageDescription

let package = Package(
  name: "RunnerExtensions",
  platforms: [.iOS({xcodeproj2xtool.sw_sy(platform)})],
  targets: [
{"".join(target_blocks)}  ]
)
"""
    with open(os.path.join(out_dir, "Package.swift"), "w") as f:
        f.write(manifest)
    with open(os.path.join(out_dir, "plan.json"), "w") as f:
        json.dump({"platform": platform, "extensions": extensions}, f, indent=1)
    if extensions:
        print(f"extensions: {', '.join(e['name'] for e in extensions)} (iOS {platform}+)")
    else:
        print("no embedded app extensions; nothing to build")
    for warning in gen.warnings:
        print(warning, file=sys.stderr)
    return {"extensions": extensions, "platform": platform, "warnings": gen.warnings}


def self_test():
    proj = r"""// !$*UTF8*$!
{
	archiveVersion = 1;
	objects = {

/* Begin PBXBuildFile section */
		EEEE00000000000000000001 /* WidgetExt.appex in CopyFiles */ = {isa = PBXBuildFile; fileRef = AAAA00000000000000000006 /* WidgetExt.appex */; };
/* End PBXBuildFile section */

/* Begin PBXCopyFilesBuildPhase section */
		EEEE00000000000000000002 /* CopyFiles */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				EEEE00000000000000000001 /* WidgetExt.appex in CopyFiles */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		AAAA00000000000000000001 /* Runner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Runner.app; sourceTree = BUILT_PRODUCTS_DIR; };
		AAAA00000000000000000006 /* WidgetExt.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = WidgetExt.appex; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		EEEE00000000000000000003 /* Exceptions for "Widget" folder in "WidgetExt" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = AAAA00000000000000000004 /* WidgetExt */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		AAAA00000000000000000007 /* Widget */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				EEEE00000000000000000003 /* Exceptions for "Widget" folder in "WidgetExt" target */,
			);
			explicitFileTypes = {
			};
			explicitFolders = (
			);
			path = Widget;
			sourceTree = "<group>";
		};
		AAAA00000000000000000008 /* Bare */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
			);
			explicitFileTypes = {
			};
			explicitFolders = (
			);
			path = Bare;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXGroup section */
		AAAA00000000000000000009 /* main */ = {
			isa = PBXGroup;
			children = (
				AAAA00000000000000000007 /* Widget */,
				AAAA00000000000000000008 /* Bare */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AAAA00000000000000000002 /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CCCC00000000000000000001 /* Build configuration list for PBXNativeTarget "Runner" */;
			buildPhases = (
				EEEE00000000000000000002 /* CopyFiles */,
			);
			buildRules = (
			);
			dependencies = (
				EEEE00000000000000000004 /* PBXTargetDependency */,
				EEEE00000000000000000006 /* PBXTargetDependency */,
			);
			name = Runner;
			productName = Runner;
			productReference = AAAA00000000000000000001 /* Runner.app */;
			productType = "com.apple.product-type.application";
		};
		AAAA00000000000000000004 /* WidgetExt */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CCCC00000000000000000002 /* Build configuration list for PBXNativeTarget "WidgetExt" */;
			buildPhases = (
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AAAA00000000000000000007 /* Widget */,
			);
			name = WidgetExt;
			productName = WidgetExt;
			productReference = AAAA00000000000000000006 /* WidgetExt.appex */;
			productType = "com.apple.product-type.app-extension";
		};
		AAAA00000000000000000005 /* BareExt */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CCCC00000000000000000003 /* Build configuration list for PBXNativeTarget "BareExt" */;
			buildPhases = (
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AAAA00000000000000000008 /* Bare */,
			);
			name = BareExt;
			productName = BareExt;
			productType = "com.apple.product-type.app-extension";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AAAA00000000000000000000 /* Project object */ = {
			isa = PBXProject;
			developmentRegion = en;
			mainGroup = AAAA00000000000000000009 /* main */;
			rootObject = AAAA00000000000000000000 /* Project object */;
		};
/* End PBXProject section */

/* Begin PBXTargetDependency section */
		EEEE00000000000000000006 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AAAA00000000000000000005 /* BareExt */;
		};
		EEEE00000000000000000004 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AAAA00000000000000000004 /* WidgetExt */;
			targetProxy = EEEE00000000000000000005 /* PBXContainerItemProxy */;
		};
		EEEE00000000000000000005 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AAAA00000000000000000000 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AAAA00000000000000000004;
			remoteInfo = WidgetExt;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		DDDD00000000000000000001 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Runner/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.App;
			};
			name = Release;
		};
		DDDD00000000000000000002 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Widget/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Widget;
				IPHONEOS_DEPLOYMENT_TARGET = 15.4;
				MARKETING_VERSION = 2.5;
				CURRENT_PROJECT_VERSION = 7;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.App.Widget;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		DDDD00000000000000000003 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.App.Bare;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		CCCC00000000000000000001 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DDDD00000000000000000001 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		CCCC00000000000000000002 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DDDD00000000000000000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		CCCC00000000000000000003 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DDDD00000000000000000003 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = AAAA00000000000000000000 /* Project object */;
}
"""
    root = tempfile.mkdtemp()
    try:
        proj_dir = os.path.join(root, "App", "ios")
        os.makedirs(os.path.join(proj_dir, "Runner.xcodeproj"))
        os.makedirs(os.path.join(proj_dir, "Runner"))
        widget = os.path.join(proj_dir, "Widget")
        os.makedirs(os.path.join(widget, "Assets.xcassets", "Color.colorset"))
        os.makedirs(os.path.join(proj_dir, "Bare"))
        with open(os.path.join(proj_dir, "Runner.xcodeproj", "project.pbxproj"), "w") as f:
            f.write(proj)
        with open(os.path.join(widget, "W.swift"), "w") as f:
            f.write("import WidgetKit\nimport SwiftUI\n")
        with open(os.path.join(widget, "Info.plist"), "wb") as f:
            plistlib.dump({"NSExtension": {"NSExtensionPointIdentifier":
                                           "com.apple.widgetkit-extension"}}, f)
        with open(os.path.join(widget, "Localizable.xcstrings"), "w") as f:
            f.write('{"sourceLanguage" : "en","strings" : {}}')
        with open(os.path.join(widget, "Assets.xcassets", "Contents.json"), "w") as f:
            f.write('{"info":{"author":"xcode","version":1}}')
        with open(os.path.join(widget, "Assets.xcassets", "Color.colorset", "Contents.json"), "w") as f:
            f.write('{"colors":[],"info":{"author":"xcode","version":1}}')
        with open(os.path.join(proj_dir, "Runner", "Info.plist"), "wb") as f:
            plistlib.dump({"CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)"}, f)
        with open(os.path.join(proj_dir, "Bare", "Notes.md"), "w") as f:
            f.write("nothing buildable here")

        out = os.path.join(root, "out")
        os.makedirs(out)
        result = plan(app=os.path.join(root, "App"), out_dir=out, configuration="Release")
        extensions, platform = result["extensions"], result["platform"]

        assert platform == "15.4", platform
        (ext,) = extensions
        assert ext["name"] == "WidgetExt"
        assert ext["bundle_id"] == "com.example.App.Widget"
        assert ext["min_ios"] == "15.4"
        assert len(ext["assets"]) == 1 and ext["assets"][0].endswith("Widget/Assets.xcassets")
        assert len(ext["strings"]) == 1 and ext["strings"][0].endswith("Localizable.xcstrings")
        assert ext["resources"] == [], ext["resources"]
        info = plistlib.load(open(ext["info_plist"], "rb"))
        assert info["CFBundlePackageType"] == "XPC!"
        assert info["CFBundleIdentifier"] == "com.example.App.Widget"
        assert info["CFBundleShortVersionString"] == "2.5"
        assert info["CFBundleVersion"] == "7"
        assert info["MinimumOSVersion"] == "15.4"
        assert info["CFBundleDisplayName"] == "Widget"
        assert info["UIDeviceFamily"] == [1, 2]
        assert info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
        link = os.path.join(out, "Sources", "WidgetExt", "Widget")
        assert os.path.islink(link) and os.path.isdir(link)
        manifest = open(os.path.join(out, "Package.swift")).read()
        assert '"WidgetExt"' in manifest and "_NSExtensionMain" in manifest
        assert "BareExt" not in manifest  # no Swift sources: skipped with a warning
        assert any("no Swift sources" in w for w in result["warnings"]), result["warnings"]
        print("self-test ok")
    finally:
        shutil.rmtree(root)
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    if len(sys.argv) != 4:
        sys.exit("usage: gen-extensions.py <flutter app dir> <output package dir> <configuration>"
                 " | gen-extensions.py --self-test")
    os.makedirs(sys.argv[2], exist_ok=True)
    plan(sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3])
    sys.exit(0)
