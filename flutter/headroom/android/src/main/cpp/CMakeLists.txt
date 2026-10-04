cmake_minimum_required(VERSION 3.22.1)
project(headroom C)

# CHeadroom/ is the Swift package's C core, copied verbatim by
# tool/sync_native.sh; headroom_jni.c is the only file that belongs here.
add_library(headroom SHARED
    CHeadroom/triad.c
    CHeadroom/platform.c
    headroom_jni.c
)
target_include_directories(headroom PRIVATE CHeadroom/include)

# The triad is a measurement kernel: it is compiled at -O3 in every build
# type, after the build type's own flags, so a debug `flutter run` still
# measures a CPU ceiling. On arm64 the compiler predefines __ARM_NEON, which
# selects the core's intrinsics path; headroom_c_optimized() reports the
# optimisation level the report's basis depends on.
target_compile_options(headroom PRIVATE -O3 -Wall -Wextra)

# 32-bit ARM: the NDK's default -march=armv7-a defines __ARM_NEON but not
# __ARM_FEATURE_FMA, which the core's vfmaq_f32 needs. Every device on API 29
# or later has VFPv4, so the fused-multiply-add NEON unit is selected here.
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(headroom PRIVATE -mfpu=neon-vfpv4)
endif()
