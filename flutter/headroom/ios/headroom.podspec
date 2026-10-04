#
# The native side of the headroom Flutter plugin: the probe layer of the
# Headroom Swift package plus its C core, compiled as one pod.
#
# Everything under Classes/CHeadroom and Classes/Core is copied from the Swift
# package by tool/sync_native.sh and must not be edited here.
#
Pod::Spec.new do |s|
  s.name             = 'headroom'
  s.version          = '0.1.0'
  s.summary          = 'A two-second on-device probe of memory bandwidth for LLM decode estimates.'
  s.description      = <<-DESC
Measures this device's memory-bandwidth ceiling (a STREAM triad on the GPU
through Metal and on the CPU through a C kernel) and records the conditions it
ran under, so the Dart side can say how fast an LLM of a given size will
decode and whether it fits, with a basis on every figure.
                       DESC
  s.homepage         = 'https://github.com/Umer9538/headroom'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Muhammad Umer' => 'https://github.com/Umer9538' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '17.0'
  s.dependency 'Flutter'

  # The plugin glue, the Swift probe layer and the C core. The C header is not
  # a pod header: Swift reaches it through Classes/CHeadroom/module.modulemap,
  # so the core's `import CHeadroom` resolves unchanged.
  s.source_files = 'Classes/**/*.{swift,c}'
  s.preserve_paths = 'Classes/CHeadroom/include/*.h', 'Classes/CHeadroom/module.modulemap'
  s.resource_bundles = { 'headroom_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.frameworks = 'Metal'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_INCLUDE_PATHS' => '"$(PODS_TARGET_SRCROOT)/Classes/CHeadroom"',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Classes/CHeadroom/include"',
    # The triad is a measurement kernel: the C files are compiled at -O3 in
    # every configuration, so a debug `flutter run` still measures a CPU
    # ceiling. Swift keeps Xcode's per-configuration defaults.
    'GCC_OPTIMIZATION_LEVEL' => '3',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '6.0'
end
