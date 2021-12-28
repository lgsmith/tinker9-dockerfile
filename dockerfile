# MUST match variables of same name below. NOT global; outer scope only.
ARG datever=20.9
# Define the cuda version (for driver compat across all nodes).
ARG cudaver=10.1
# define some paths that will be used throughout
# Define a top-dir for the build. Should be '/app' for RIS compat.
ARG topdir='/app'
ARG srcdir=$topdir/tinker9
ARG builddir=$srcdir/build
# Start stage 0, 'build' stage, here.
# Naming convention changed over time, so won't work for arb. date-versions
# consult https://ngc.nvidia.com/catalog/containers/nvidia:nvhpc/tags
# FROM nvcr.io/nvidia/nvhpc:$datever-devel-cuda_multi-ubuntu20.04 as build
FROM nvcr.io/nvidia/nvhpc:$datever-devel-ubuntu20.04 as build
# ARG statements scoped to outside of and within from statements,
# which delimit the stages of a build. Restating them here wihtout
# defaults exposes them to this stage, using either prior defaults 
ARG datever
ARG cudaver
ARG topdir
ARG srcdir
ARG builddir
# Purge cmake to replace with more modern version needed for cuda.
RUN apt purge -y --auto-remove cmake
# install and update gcc so that we are on a version compatible 
# with cudaver also install ca-certs and libssl so we can use wget.
RUN apt update && apt install -y --reinstall\
 ca-certificates\
 gcc-8\
 g++-8\
 gfortran-8\
 libssl-dev
# now make these libs and compilers are the main ones
RUN update-alternatives --install \
    /usr/bin/gcc gcc /usr/bin/gcc-8 80 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-8 \
    --slave /usr/bin/gfortran gfortran /usr/bin/gfortran-8 \
    --slave /usr/bin/gcov gcov /usr/bin/gcov-8
# get the cmake source and build it
RUN export CC=gcc; export CXX=g++\
    version=3.20 &&\
    build=0 &&\
    mkdir ~/temp &&\
    cd ~/temp &&\
    wget https://cmake.org/files/v$version/cmake-$version.$build.tar.gz &&\
    tar -xzvf cmake-$version.$build.tar.gz &&\
    cd cmake-$version.$build/ &&\
    export CC=gcc &&\
    export CXX=g++ &&\
    ./bootstrap &&\
    make -j$(nproc) &&\
    make install
# create some default args using the global args brought in above.
ARG cudadir=/opt/nvidia/hpc_sdk/Linux_x86_64/$datever/cuda/$cudaver
ARG mathlibs=/opt/nvidia/hpc_sdk/Linux_x86_64/$datever/math_libs/$cudaver/lib64
ARG mathincludes=/opt/nvidia/hpc_sdk/Linux_x86_64/$datever/math_libs/$cudaver/include
# Change to the topdir, so that we can do the install there.
WORKDIR $topdir
# Get the tinker9 source
RUN git clone https://github.com/TinkerTools/tinker9.git
WORKDIR $srcdir
# Get the cuda paths correctly defined in the cmake files.
RUN sed -i "55 i \ \ \ \ \ \ -L$mathlibs" cmake/device.cmake;\
    sed -i "89 i \ \ \ \ \ \ -L$mathlibs" cmake/device.cmake;\
    sed -i "302 i list (APPEND T9_SYS_INCPATH $mathincludes)" CMakeLists.txt
# Tinker9 stuff. Part of the recommended install procedure to integrate with T8.
RUN git submodule update --init
# T9 cmake call.
RUN cmake $srcdir -B $builddir\
 -DCMAKE_BUILD_TYPE=Release\
 -DCUDA_DIR=$cudadir\
 -DFFTW_DIR=/home/tinker9/tinker/fftw\
 -DCMAKE_CXX_COMPILER=g++\
 -DCMAKE_C_COMPILER=gcc\
 -DCMAKE_Fortran_COMPILER=gfortran\
 -DCMAKE_INSTALL_PREFIX=$topdir\
 -DCOMPUTE_CAPABILITY=70,75
WORKDIR $builddir
# NOTE: if the nvidia-container-toolkit isn't working properly
# You will need to do these last steps manually by shelling 
# into the container. The build should run, but make test won't.
RUN make -j$(nproc)
# RUN make install
RUN make install
    
# Start runtime stage here
FROM nvcr.io/nvidia/nvhpc:$datever-runtime-cuda$cudaver-ubuntu20.04 as runtime
# args from above have gone out of scope and must be redefined here.
ARG topdir
ARG srcdir
ARG datever
ARG cudave
# use build stage to copy objects/execs into runtime container.
COPY --from=build $srcdir $topdir

RUN set -ex;\
 apt-get update;\
 DEBIAN_FRONTEND=noninteractive apt-get install -y\
 gcc-8 g++-8 gfortran-8\
 && apt-get clean
# gpu-m is where the gpu executables are kept in t9 install.
ENV PATH=$PATH:$topdir/gpu-m
# make certain that the LD_LIBRARY_PATH is correct
ENV LD_LIBRARY_PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/$datever/math_libs/$cudaver/lib64/:${LD_LIBRARY_PATH}
