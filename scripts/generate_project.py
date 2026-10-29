#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generator (no CocoaPods / XcodeGen)."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def identifier(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def openstep(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        entries = [f"{pad}\t{json.dumps(str(key))} = {openstep(item, indent + 1)};" for key, item in value.items()]
        return "{\n" + "\n".join(entries) + f"\n{pad}}}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{pad}\t{openstep(item, indent + 1)}," for item in value) + f"\n{pad})"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


def generate_project() -> str:
    objects = {}

    def add(key, isa, **attributes):
        uid = identifier(key)
        if uid in objects:
            raise ValueError(f"Duplicate object: {key}")
        objects[uid] = dict(isa=isa, **attributes)
        return uid

    def file_group(directory: Path, key: str):
        refs = []
        for path in sorted(directory.iterdir()):
            if path.name.startswith("."):
                continue
            relative = path.relative_to(ROOT).as_posix()
            if path.is_dir() and path.suffix != ".xcassets":
                refs.append(file_group(path, relative))
            else:
                types = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".json": "text.json", ".xcprivacy": "text.xml", ".xcassets": "folder.assetcatalog"}
                refs.append(add("file:" + relative, "PBXFileReference", lastKnownFileType=types.get(path.suffix, "text"), path=path.name, sourceTree="<group>"))
        return add("group:" + key, "PBXGroup", children=refs, path=directory.name, sourceTree="<group>")

    app_group = file_group(ROOT / "VietMap", "VietMap")
    test_group = file_group(ROOT / "VietMapTests", "VietMapTests")
    ui_group = file_group(ROOT / "VietMapUITests", "VietMapUITests")
    package_ref = add("local-package", "XCLocalSwiftPackageReference", relativePath="Packages/VietMapCore")
    project_id = identifier("project")
    targets = []
    product_refs = []
    for name, folder, kind in [
        ("VietMap", "VietMap", "com.apple.product-type.application"),
        ("VietMapTests", "VietMapTests", "com.apple.product-type.bundle.unit-test"),
        ("VietMapUITests", "VietMapUITests", "com.apple.product-type.bundle.ui-testing"),
    ]:
        is_app = name == "VietMap"
        is_ui = name == "VietMapUITests"
        product = add("product:" + name, "PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle", includeInIndex=0,
                      path=name + (".app" if is_app else ".xctest"), sourceTree="BUILT_PRODUCTS_DIR")
        product_refs.append(product)
        sources = []
        for path in sorted((ROOT / folder).rglob("*.swift")):
            relative = path.relative_to(ROOT).as_posix()
            sources.append(add("source:" + relative, "PBXBuildFile", fileRef=identifier("file:" + relative)))
        source_phase = add("sources:" + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
        resources = []
        if is_app:
            for relative in ["VietMap/Resources/Assets.xcassets", "VietMap/Resources/PrivacyInfo.xcprivacy", "VietMap/Resources/demo-traffic.json"]:
                resources.append(add("resource:" + relative, "PBXBuildFile", fileRef=identifier("file:" + relative)))
        resource_phase = add("resources:" + name, "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
        package_products, framework_files = [], []
        if not is_ui:
            dependency = add("package-product:" + name, "XCSwiftPackageProductDependency", productName="VietMapCore", package=package_ref)
            package_products.append(dependency)
            framework_files.append(add("link-package:" + name, "PBXBuildFile", productRef=dependency))
        framework_phase = add("frameworks:" + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=framework_files, runOnlyForDeploymentPostprocessing=0)
        configs = []
        for config in ("Debug", "Release"):
            settings = {
                "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "vn.tradingleak.vietmap" + ("" if is_app else ".uitests" if is_ui else ".tests"),
                "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "targeted", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
                "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY": "1,2",
                "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1",
                "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
                "GENERATE_INFOPLIST_FILE": "NO" if is_app else "YES",
            }
            if is_app:
                settings.update({"INFOPLIST_FILE": "VietMap/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor"})
            elif is_ui:
                settings["TEST_TARGET_NAME"] = "VietMap"
            else:
                settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/VietMap.app/VietMap"})
            configs.append(add(f"config:{name}:{config}", "XCBuildConfiguration", name=config, buildSettings=settings))
        config_list = add("configs:" + name, "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
        target_dependencies = []
        if not is_app:
            proxy = add("proxy:" + name, "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=identifier("target:VietMap"), remoteInfo="VietMap")
            target_dependencies.append(add("target-dependency:" + name, "PBXTargetDependency", target=identifier("target:VietMap"), targetProxy=proxy))
        targets.append(add("target:" + name, "PBXNativeTarget", buildConfigurationList=config_list, buildPhases=[source_phase, framework_phase, resource_phase],
                           buildRules=[], dependencies=target_dependencies, name=name, packageProductDependencies=package_products, productName=name,
                           productReference=product, productType=kind))
    products_group = add("group:Products", "PBXGroup", children=product_refs, name="Products", sourceTree="<group>")
    main_group = add("group:root", "PBXGroup", children=[app_group, test_group, ui_group, products_group], sourceTree="<group>")
    configs = []
    for config in ("Debug", "Release"):
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
            "CLANG_WARN_BOOL_CONVERSION": "YES", "CLANG_WARN_CONSTANT_CONVERSION": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
            "CLANG_WARN_UNREACHABLE_CODE": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_NO_COMMON_BLOCKS": "YES", "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES", "GCC_WARN_UNDECLARED_SELECTOR": "YES",
            "GCC_WARN_UNUSED_FUNCTION": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "DEBUG"] if config == "Debug" else ["$(inherited)"],
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO", "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO",
        }
        if config == "Release":
            settings.update({"SWIFT_COMPILATION_MODE": "wholemodule", "ENABLE_NS_ASSERTIONS": "NO", "VALIDATE_PRODUCT": "YES"})
        configs.append(add("config:project:" + config, "XCBuildConfiguration", name=config, buildSettings=settings))
    config_list = add("configs:project", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600",
        "TargetAttributes": {identifier("target:" + name): {"CreatedOnToolsVersion": "16.0"} for name in ("VietMap", "VietMapTests", "VietMapUITests")}},
        buildConfigurationList=config_list, compatibilityVersion="Xcode 14.0", developmentRegion="vi", hasScannedForEncodings=0,
        knownRegions=["vi", "en", "Base"], mainGroup=main_group, packageReferences=[package_ref], productRefGroup=products_group,
        projectDirPath="", projectRoot="", targets=targets)
    return "// !$*UTF8*$!\n" + openstep({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n"


def generate_scheme() -> str:
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.7")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")

    def reference(parent, name):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=identifier("target:" + name),
                      BuildableName=name + (".app" if name == "VietMap" else ".xctest"), BlueprintName=name, ReferencedContainer="container:VietMap.xcodeproj")

    for name in ("VietMap", "VietMapTests", "VietMapUITests"):
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if name == "VietMap" else "NO",
                              buildForProfiling="YES" if name == "VietMap" else "NO", buildForArchiving="YES" if name == "VietMap" else "NO", buildForAnalyzing="YES")
        reference(entry, name)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    for name in ("VietMapTests", "VietMapUITests"):
        reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), name)
    reference(ET.SubElement(test, "MacroExpansion"), "VietMap")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "VietMap")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "VietMap")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme, space="   ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(scheme, encoding="unicode") + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail rather than writing when the checked-in project is stale")
    args = parser.parse_args()
    files = {ROOT / "VietMap.xcodeproj/project.pbxproj": generate_project(), ROOT / "VietMap.xcodeproj/xcshareddata/xcschemes/VietMap.xcscheme": generate_scheme()}
    for path, content in files.items():
        if args.check:
            if not path.exists() or path.read_text() != content:
                print(f"Out of date: {path.relative_to(ROOT)}; run python3 scripts/generate_project.py", file=sys.stderr)
                return 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
