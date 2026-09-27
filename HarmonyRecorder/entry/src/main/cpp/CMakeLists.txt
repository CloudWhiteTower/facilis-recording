cmake_minimum_required(VERSION 3.5.0)
project(facilis_flac)

add_library(facilis_flac SHARED flac_recorder.cpp audio_conversion.cpp)
target_compile_features(facilis_flac PRIVATE cxx_std_17)
target_compile_options(facilis_flac PRIVATE -Wall -Wextra -Werror=return-type -fexceptions)
target_link_libraries(facilis_flac PUBLIC
    libace_napi.z.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libnative_media_acodec.so
    libnative_media_avmuxer.so
    libnative_media_avsource.so
    libnative_media_avdemuxer.so)
