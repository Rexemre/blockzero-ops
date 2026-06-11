cmake_minimum_required(VERSION 3.20)

project(blockzero-pool-miner CXX)



set(CMAKE_CXX_STANDARD 20)

set(CMAKE_CXX_STANDARD_REQUIRED ON)



find_package(Threads REQUIRED)



include(FetchContent)



FetchContent_Declare(

  randomx

  GIT_REPOSITORY https://github.com/tevador/RandomX.git

  GIT_TAG master

)

set(RANDOMX_BUILD_TESTS OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(randomx)



set(USE_TLS ON CACHE BOOL "" FORCE)

set(USE_OPEN_SSL ON CACHE BOOL "" FORCE)

set(USE_ZLIB OFF CACHE BOOL "" FORCE)

FetchContent_Declare(

  ixwebsocket

  GIT_REPOSITORY https://github.com/machinezone/IXWebSocket.git

  GIT_TAG v11.4.4

)

FetchContent_MakeAvailable(ixwebsocket)



add_executable(bz-pool-miner

  bz_pool_miner.cpp

  miner_config.cpp

  stratum_client.cpp

  pow_util.cpp

)



target_include_directories(bz-pool-miner PRIVATE

  ${randomx_SOURCE_DIR}/src

)



target_link_libraries(bz-pool-miner PRIVATE

  randomx

  ixwebsocket

  Threads::Threads

)



if(WIN32)

  target_link_libraries(bz-pool-miner PRIVATE ws2_32 crypt32)

endif()



install(TARGETS bz-pool-miner RUNTIME DESTINATION bin)


