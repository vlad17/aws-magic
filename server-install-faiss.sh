#!/bin/bash

if [ -d /opt/faiss ]; then
    echo "faiss installed"
fi

set -e

cd /tmp
git clone https://github.com/facebookresearch/faiss.git
cp -rf faiss /opt
cd /opt/faiss

apt-get -y install libopenblas-dev swig
pyflags=$(echo -I$(python -c "import distutils.sysconfig; print(distutils.sysconfig.get_python_inc())") -I$(python -c "import numpy ; print(numpy.get_include())"))
echo 'CC=g++
CFLAGS=-fPIC -m64 -Wall -g -O3 -mavx -msse4 -mpopcnt -fopenmp -Wno-sign-compare -std=c++11 -fopenmp
LDFLAGS=-g -fPIC  -fopenmp
SHAREDEXT=so
SHAREDFLAGS=-shared
FAISSSHAREDFLAGS=-shared
BLASCFLAGS=-DFINTEGER=int
BLASLDFLAGS?=/usr/lib/libopenblas.so.0
SWIGEXEC=swig
PYTHONCFLAGS='"$pyflags"'
CC11=g++
CUDAROOT=/usr/local/cuda-8.0/
CUDACFLAGS=-I$(CUDAROOT)/include
NVCC=$(CUDAROOT)/bin/nvcc
NVCCFLAGS= $(CUDAFLAGS) \
   -I $(CUDAROOT)/targets/x86_64-linux/include/ \
   -Xcompiler -fPIC \
   -Xcudafe --diag_suppress=unrecognized_attribute \
   -gencode arch=compute_35,code="compute_35" \
   -gencode arch=compute_52,code="compute_52" \
   -gencode arch=compute_60,code="compute_60" \
   --std c++11 -lineinfo \
   -ccbin $(CC11) -DFAISS_USE_FLOAT16
BLASLDFLAGSNVCC=-Xlinker $(BLASLDFLAGS)
BLASLDFLAGSSONVCC=-Xlinker  $(BLASLDFLAGS)' > makefile.inc
make -j$(nproc) tests/test_blas
./tests/test_blas
make -j$(nproc)
make -j$(nproc) tests/demo_ivfpq_indexing
tests/demo_ivfpq_indexing
make py
cd gpu
make -j$(nproc)
make -j$(nproc) test/demo_ivfpq_indexing_gpu
test/demo_ivfpq_indexing_gpu
make py
cd ..
python -c "import faiss"
python -c "import _swigfaiss_gpu"
