
// gen-xcodeproj.mjs — 生成可直接用 Xcode 打开/命令行构建的工程文件（纯拼接，无模板字符串）
import fs from "node:fs";
import path from "node:path";

const ROOT = "E:/ds/ARTEXX-iOS/ios";
const APP = "ARTEXX";
const projDir = path.join(ROOT, APP + ".xcodeproj");
fs.mkdirSync(projDir, { recursive: true });

function walk(dir, base) {
  base = base || "";
  let out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = base ? base + "/" + e.name : e.name;
    if (e.isDirectory()) {
      if (e.name.endsWith(".xcassets")) { out.push({ rel: rel, type: "assets" }); continue; }
      if (e.name === "webui") { out.push({ rel: rel, type: "folder" }); continue; }
      out = out.concat(walk(path.join(dir, e.name), rel));
    } else {
      const ext = path.extname(e.name);
      if (ext === ".swift") out.push({ rel: rel, type: "swift" });
      else if (e.name === "Info.plist") out.push({ rel: rel, type: "plist" });
      else if (ext === ".json" || ext === ".gz" || ext === ".sqlite" || ext === ".png") out.push({ rel: rel, type: "resource" });
    }
  }
  return out;
}
const files = walk(path.join(ROOT, APP), "");

let counter = 0;
function uid() { return (0x1000000 + (++counter)).toString(16).toUpperCase().padStart(24, "0"); }

const fileRefs = {}, buildFiles = {};
for (const f of files) {
  if (f.type === "plist") continue;
  fileRefs[f.rel] = uid();
  buildFiles[f.rel] = uid();
}
const swift = files.filter(function (f) { return f.type === "swift"; });
const resources = files.filter(function (f) { return f.type === "resource" || f.type === "assets" || f.type === "folder"; });

const L = [];
function p(s) { L.push(s); }

p("// !$*UTF8*$!");
p("{");
p("\tarchiveVersion = 1;");
p("\tclasses = {");
p("\t};");
p("\tobjectVersion = 56;");
p("\tobjects = {");

p("\n/* Begin PBXBuildFile section */");
for (const f of swift.concat(resources)) {
  const n = path.basename(f.rel);
  p("\t\t" + buildFiles[f.rel] + " /* " + n + " */ = {isa = PBXBuildFile; fileRef = " + fileRefs[f.rel] + " /* " + n + " */; };");
}
p("/* End PBXBuildFile section */");

p("\n/* Begin PBXFileReference section */");
for (const f of files) {
  if (f.type === "plist") continue;
  const n = path.basename(f.rel);
  let kind = "sourcecode.swift";
  if (f.type === "assets") kind = "folder.assetcatalog";
  else if (f.type === "folder") kind = "folder";
  else if (f.type === "resource") kind = path.extname(f.rel) === ".json" ? "text.json" : "file";
  p('\t\t' + fileRefs[f.rel] + " /* " + n + ' */ = {isa = PBXFileReference; lastKnownFileType = ' + kind + '; name = "' + n + '"; path = "' + APP + '/' + f.rel + '"; sourceTree = "SOURCE_ROOT"; };');
}
const appRef = uid();
p("\t\t" + appRef + " /* " + APP + '.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ' + APP + ".app; sourceTree = BUILT_PRODUCTS_DIR; };");
p("/* End PBXFileReference section */");

const groupsByDir = {};
for (const f of files) {
  if (f.type === "plist") continue;
  const dir = path.dirname(f.rel) === "." ? "" : path.dirname(f.rel);
  if (!groupsByDir[dir]) groupsByDir[dir] = [];
  groupsByDir[dir].push(f);
}
const groupUid = {};
for (const dir of Object.keys(groupsByDir)) groupUid[dir] = uid();
const mainGroup = uid();

p("\n/* Begin PBXGroup section */");
const appGroup = uid();
p("\t\t" + mainGroup + " = {isa = PBXGroup; children = (");
p("\t\t\t" + appGroup + " /* " + APP + " */,");
p("\t\t\t" + appRef + " /* " + APP + ".app */,");
p('\t\t); sourceTree = "<group>"; };');
p("\t\t" + appGroup + " /* " + APP + " */ = {isa = PBXGroup; children = (");
for (const f of files) {
  if (f.type === "plist") continue;
  p("\t\t\t" + fileRefs[f.rel] + " /* " + path.basename(f.rel) + " */,");
}
p('\t\t); name = "' + APP + '"; sourceTree = "<group>"; };');
p("/* End PBXGroup section */");

const appTarget = uid(), sourcesPhase = uid(), resourcesPhase = uid(), frameworksPhase = uid();
const projectUid = uid(), configListProject = uid(), configListTarget = uid();
const dbgProj = uid(), relProj = uid(), dbgTarget = uid(), relTarget = uid();

p("\n/* Begin PBXNativeTarget section */");
p("\t\t" + appTarget + " /* " + APP + " */ = {");
p("\t\t\tisa = PBXNativeTarget;");
p("\t\t\tbuildConfigurationList = " + configListTarget + " /* target config list */;");
p("\t\t\tbuildPhases = (");
p("\t\t\t\t" + sourcesPhase + " /* Sources */,");
p("\t\t\t\t" + frameworksPhase + " /* Frameworks */,");
p("\t\t\t\t" + resourcesPhase + " /* Resources */,");
p("\t\t\t);");
p("\t\t\tbuildRules = (\n\t\t\t);");
p("\t\t\tdependencies = (\n\t\t\t);");
p("\t\t\tname = " + APP + ";");
p("\t\t\tproductName = " + APP + ";");
p("\t\t\tproductReference = " + appRef + " /* " + APP + ".app */;");
p('\t\t\tproductType = "com.apple.product-type.application";');
p("\t\t};");
p("/* End PBXNativeTarget section */");

p("\n/* Begin PBXProject section */");
p("\t\t" + projectUid + " /* Project object */ = {");
p("\t\t\tisa = PBXProject;");
p("\t\t\tattributes = {");
p("\t\t\t\tBuildIndependentTargetsInParallel = 1;");
p("\t\t\t\tLastSwiftUpdateCheck = 1500;");
p("\t\t\t\tLastUpgradeCheck = 1500;");
p("\t\t\t\tTargetAttributes = {");
p("\t\t\t\t\t" + appTarget + " = { CreatedOnToolsVersion = 15.0; };");
p("\t\t\t\t};");
p("\t\t\t};");
p("\t\t\tbuildConfigurationList = " + configListProject + " /* project config list */;");
p('\t\t\tcompatibilityVersion = "Xcode 14.0";');
p("\t\t\tdevelopmentRegion = zh_CN;");
p("\t\t\thasScannedForEncodings = 0;");
p("\t\t\tknownRegions = (\n\t\t\t\tzh_CN,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);");
p("\t\t\tmainGroup = " + mainGroup + ";");
p("\t\t\tproductRefGroup = " + mainGroup + ";");
p('\t\t\tprojectDirPath = "";');
p('\t\t\tprojectRoot = "";');
p("\t\t\ttargets = (");
p("\t\t\t\t" + appTarget + " /* " + APP + " */,");
p("\t\t\t);");
p("\t\t};");
p("/* End PBXProject section */");

p("\n/* Begin PBXSourcesBuildPhase section */");
p("\t\t" + sourcesPhase + " /* Sources */ = {");
p("\t\t\tisa = PBXSourcesBuildPhase;");
p("\t\t\tbuildActionMask = 2147483647;");
p("\t\t\tfiles = (");
for (const f of swift) p("\t\t\t\t" + buildFiles[f.rel] + " /* " + path.basename(f.rel) + " in Sources */,");
p("\t\t\t);");
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
p("\t\t};");
p("/* End PBXSourcesBuildPhase section */");

p("\n/* Begin PBXResourcesBuildPhase section */");
p("\t\t" + resourcesPhase + " /* Resources */ = {");
p("\t\t\tisa = PBXResourcesBuildPhase;");
p("\t\t\tbuildActionMask = 2147483647;");
p("\t\t\tfiles = (");
for (const f of resources) p("\t\t\t\t" + buildFiles[f.rel] + " /* " + path.basename(f.rel) + " in Resources */,");
p("\t\t\t);");
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
p("\t\t};");
p("/* End PBXResourcesBuildPhase section */");

p("\n/* Begin PBXFrameworksBuildPhase section */");
p("\t\t" + frameworksPhase + " /* Frameworks */ = {");
p("\t\t\tisa = PBXFrameworksBuildPhase;");
p("\t\t\tbuildActionMask = 2147483647;");
p("\t\t\tfiles = (\n\t\t\t);");
p("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
p("\t\t};");
p("/* End PBXFrameworksBuildPhase section */");

const projSettings = [
  "ALWAYS_SEARCH_USER_PATHS = NO;",
  "CLANG_ENABLE_MODULES = YES;",
  "CLANG_ENABLE_OBJC_ARC = YES;",
  "ENABLE_BITCODE = NO;",
  "GCC_C_LANGUAGE_STANDARD = gnu17;",
  "IPHONEOS_DEPLOYMENT_TARGET = 16.0;",
  "SDKROOT = iphoneos;",
  "SWIFT_VERSION = 5.0;",
  "ENABLE_USER_SCRIPT_SANDBOXING = NO;"
];
function appSettings(debug) {
  const s = [
    "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
    "CODE_SIGN_STYLE = Automatic;",
    "CURRENT_PROJECT_VERSION = 1;",
    "ENABLE_PREVIEWS = YES;",
    "GENERATE_INFOPLIST_FILE = NO;",
    "INFOPLIST_FILE = " + APP + "/Info.plist;",
    "IPHONEOS_DEPLOYMENT_TARGET = 16.0;",
    'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
    "MARKETING_VERSION = 1.0.0;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.artexx.ios;",
    'PRODUCT_NAME = "$(TARGET_NAME)";',
    'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
    "SWIFT_EMIT_LOC_STRINGS = YES;",
    "SWIFT_VERSION = 5.0;",
    'TARGETED_DEVICE_FAMILY = "1,2";',
    "CODE_SIGNING_ALLOWED = YES;",
    "CODE_SIGNING_REQUIRED = NO;"
  ];
  if (debug) s.push("SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;");
  return s;
}
function emitConfig(id, name, settings) {
  p("\t\t" + id + " /* " + name + " */ = {");
  p("\t\t\tisa = XCBuildConfiguration;");
  p("\t\t\tbuildSettings = {");
  for (const s of settings) p("\t\t\t\t" + s);
  p("\t\t\t};");
  p("\t\t\tname = " + name + ";");
  p("\t\t};");
}

p("\n/* Begin XCBuildConfiguration section */");
emitConfig(dbgProj, "Debug", projSettings.concat(["SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"]));
emitConfig(relProj, "Release", projSettings.concat(["SWIFT_OPTIMIZATION_LEVEL = \"-O\";", "SWIFT_COMPILATION_MODE = wholemodule;", "VALIDATE_PRODUCT = YES;"]));
emitConfig(dbgTarget, "Debug", appSettings(true));
emitConfig(relTarget, "Release", appSettings(false));
p("/* End XCBuildConfiguration section */");

p("\n/* Begin XCConfigurationList section */");
p("\t\t" + configListProject + " /* project */ = {");
p("\t\t\tisa = XCConfigurationList;");
p("\t\t\tbuildConfigurations = (");
p("\t\t\t\t" + dbgProj + " /* Debug */,");
p("\t\t\t\t" + relProj + " /* Release */,");
p("\t\t\t);");
p("\t\t\tdefaultConfigurationIsVisible = 0;");
p("\t\t\tdefaultConfigurationName = Release;");
p("\t\t};");
p("\t\t" + configListTarget + " /* target */ = {");
p("\t\t\tisa = XCConfigurationList;");
p("\t\t\tbuildConfigurations = (");
p("\t\t\t\t" + dbgTarget + " /* Debug */,");
p("\t\t\t\t" + relTarget + " /* Release */,");
p("\t\t\t);");
p("\t\t\tdefaultConfigurationIsVisible = 0;");
p("\t\t\tdefaultConfigurationName = Release;");
p("\t\t};");
p("/* End XCConfigurationList section */");

p("\t};");
p("\trootObject = " + projectUid + " /* Project object */;");
p("}");

const out = L.join("\n");
fs.writeFileSync(path.join(projDir, "project.pbxproj"), out);
console.log("pbxproj:", out.length, "bytes | files", files.length, "| swift", swift.length, "| resources", resources.length);
