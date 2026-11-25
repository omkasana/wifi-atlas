#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project for the app and WidgetKit extension."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(label, isa, **fields):
    key = ident(label); objects[key] = dict(isa=isa, **fields); return key

def file(path, kind): return add('file:'+path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')
app_files = [file(str(p.relative_to(root)), 'sourcecode.swift') for p in sorted((root/'Sources/WiFiAtlas').glob('*.swift'))]
widget_files = [file('WidgetExtension/AtlasWidgets.swift', 'sourcecode.swift')]
metadata = [file(p, 'text.plist.entitlements' if p.endswith('entitlements') else 'text.plist.xml') for p in ['Resources/Info.plist','Resources/App.entitlements','WidgetExtension/Info.plist','WidgetExtension/Widget.entitlements']]
app_product = add('app-product','PBXFileReference',explicitFileType='wrapper.application',path='WiFi Atlas.app',sourceTree='BUILT_PRODUCTS_DIR')
widget_product = add('widget-product','PBXFileReference',explicitFileType='wrapper.app-extension',path='AtlasWidgets.appex',sourceTree='BUILT_PRODUCTS_DIR')
products = add('products','PBXGroup',children=[app_product,widget_product],name='Products',sourceTree='<group>')
main = add('main','PBXGroup',children=app_files+widget_files+metadata+[products],sourceTree='<group>')
package = add('package','XCLocalSwiftPackageReference',relativePath='.')

def configs(name, settings):
    values = []
    for mode in ['Debug','Release']:
        config = dict(settings)
        config.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode=='Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if mode=='Debug' else 'dwarf-with-dsym')
        if mode=='Debug': config['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        values.append(add(name+mode,'XCBuildConfiguration',buildSettings=config,name=mode))
    return add(name+'configs','XCConfigurationList',buildConfigurations=values,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

common = dict(SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET='14.0',SWIFT_VERSION='5.0',ARCHS='arm64',CODE_SIGN_STYLE='Automatic',ENABLE_USER_SCRIPT_SANDBOXING='NO',APP_GROUP_ID='$(DEVELOPMENT_TEAM).com.wifiatlas.shared',CLANG_ENABLE_MODULES='YES')
project_configs = configs('project',common)
app_settings = dict(PRODUCT_NAME='WiFi Atlas',EXECUTABLE_NAME='WiFiAtlas',PRODUCT_MODULE_NAME='WiFiAtlas',PRODUCT_BUNDLE_IDENTIFIER='com.wifiatlas.mac',INFOPLIST_FILE='Resources/Info.plist',CODE_SIGN_ENTITLEMENTS='Resources/App.entitlements',ENABLE_HARDENED_RUNTIME='YES',GENERATE_INFOPLIST_FILE='NO',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'])
widget_settings = dict(PRODUCT_NAME='AtlasWidgets',PRODUCT_BUNDLE_IDENTIFIER='com.wifiatlas.mac.widgets',INFOPLIST_FILE='WidgetExtension/Info.plist',CODE_SIGN_ENTITLEMENTS='WidgetExtension/Widget.entitlements',APPLICATION_EXTENSION_API_ONLY='YES',ENABLE_HARDENED_RUNTIME='YES',GENERATE_INFOPLIST_FILE='NO',SKIP_INSTALL='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks','@executable_path/../../../../Frameworks'])

def phases(name, files):
    source_builds = [add(name+':src:'+f,'PBXBuildFile',fileRef=f) for f in files]
    sources = add(name+'sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=source_builds,runOnlyForDeploymentPostprocessing=0)
    dependency = add(name+'core','XCSwiftPackageProductDependency',package=package,productName='AtlasCore')
    link = add(name+'linkcore','PBXBuildFile',productRef=dependency)
    frameworks = add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[link],runOnlyForDeploymentPostprocessing=0)
    resources = add(name+'resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    return [sources,frameworks,resources],dependency

widget_phases, widget_core = phases('widget',widget_files)
widget_target = add('widgettarget','PBXNativeTarget',buildConfigurationList=configs('widget',widget_settings),buildPhases=widget_phases,buildRules=[],dependencies=[],name='AtlasWidgets',packageProductDependencies=[widget_core],productName='AtlasWidgets',productReference=widget_product,productType='com.apple.product-type.app-extension')
proxy = add('widgetproxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=widget_target,remoteInfo='AtlasWidgets')
dependency = add('widgetdependency','PBXTargetDependency',target=widget_target,targetProxy=proxy)
app_phases, app_core = phases('app',app_files)
icon_script = '''set -e
mkdir -p "$DERIVED_FILE_DIR/Atlas.iconset" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
export CLANG_MODULE_CACHE_PATH="$DERIVED_FILE_DIR/ModuleCache"
swift "$SRCROOT/scripts/icon.swift" "$DERIVED_FILE_DIR/Atlas.iconset" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Atlas.icns"
'''
icon = add('icons','PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=['$(SRCROOT)/scripts/icon.swift'],outputPaths=['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Atlas.icns'],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/bash',shellScript=icon_script)
embed_file = add('embedwidgetfile','PBXBuildFile',fileRef=widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed = add('embedwidget','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed_file],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)
app_target = add('apptarget','PBXNativeTarget',buildConfigurationList=configs('app',app_settings),buildPhases=app_phases+[icon,embed],buildRules=[],dependencies=[dependency],name='WiFiAtlas',packageProductDependencies=[app_core],productName='WiFi Atlas',productReference=app_product,productType='com.apple.product-type.application')
project = add('project','PBXProject',attributes={'LastUpgradeCheck':'1600','BuildIndependentTargetsInParallel':'YES','TargetAttributes':{app_target:{'SystemCapabilities':{'com.apple.ApplicationGroups.Mac':{'enabled':1}}},widget_target:{'SystemCapabilities':{'com.apple.ApplicationGroups.Mac':{'enabled':1}}}}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,packageReferences=[package],productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_target,widget_target])

def encode(value, depth=0):
    if isinstance(value,dict): return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+ ' = '+encode(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
    if isinstance(value,list): return '('+', '.join(encode(v,depth) for v in value)+')'
    if isinstance(value,int): return str(value)
    return json.dumps(value)
content = {'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project}
p = root/'WiFiAtlas.xcodeproj'; p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(content)+'\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="WiFi Atlas.app" BlueprintName="WiFiAtlas" ReferencedContainer="container:WiFiAtlas.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="WiFi Atlas.app" BlueprintName="WiFiAtlas" ReferencedContainer="container:WiFiAtlas.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="WiFi Atlas.app" BlueprintName="WiFiAtlas" ReferencedContainer="container:WiFiAtlas.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
folder=p/'xcshareddata/xcschemes'; folder.mkdir(parents=True,exist_ok=True); (folder/'WiFiAtlas.xcscheme').write_text(scheme)
# An extension scheme permits attaching Xcode's WidgetKit debugger.
widget_scheme=scheme.replace(app_target,widget_target).replace('WiFi Atlas.app','AtlasWidgets.appex').replace('BlueprintName="WiFiAtlas"','BlueprintName="AtlasWidgets"')
(folder/'AtlasWidgets.xcscheme').write_text(widget_scheme)
