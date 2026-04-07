cmake_minimum_required(VERSION 3.16)

project(app_demo C)

add_executable(app_demo
    src/main.c
)

target_include_directories(app_demo
    PRIVATE
        include
)
