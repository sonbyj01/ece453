CXX = g++
CXXFLAGS = -std=c++0x
CFLAGS = -Wall -Wextra -pedantic -ansi -O3
DEPS = ./dep/lodepng/lodepng.cpp ./dep/metrics/metrics.cpp
CPU_CODE = ./src/cpu/deblur.cpp

CC = aarch64-linux-gnu-g++
NVCC = /usr/local/cuda-10.0/bin/nvcc -ccbin $(CC)
NVCC_LIB = /usr/local/cuda-10.0/targets/aarch64-linux/lib
INCLUDES = /usr/local/cuda-10.0/samples/common/inc
CUDART_LIB = /usr/local/cuda-10.0/targets/aarch64-linux/lib/libcudart.so

all: deblur.o metrics.o lodepng.o
	$(CC) -o deblur deblur.o -L$(NVCC_LIB) -lcudart metrics.o lodepng.o

deblur.o: ./gpu/deblur.cu
	$(NVCC) -I. -I$(INCLUDES) -c ./gpu/deblur.cu

metrics.o: ./dep/metrics/metrics.cpp ./dep/metrics/metrics.hpp
	$(CC) -c ./dep/metrics/metrics.cpp

lodepng.o: ./lodepng/lodepng.cpp ./lodepng/lodepng.h
	$(CC) -c ./dep/lodepng/lodepng.cpp $(CFLAGS)

cpu_deblur:
	$(CXX) $(CPU_CODE) -o cpu_deblur.out $(DEPS) $(CFLAGS) $(CXXFLAGS)

clean:
	rm -rf *.exe *.o *.stackdump *~